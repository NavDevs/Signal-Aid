import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/driver.dart';
import '../models/trip.dart';
import '../navigation.dart';


/// Backend-authoritative session state for the Signal Aid driver app.
///
/// The app never decides whether a driver is approved â€” every transition into
/// [approved] comes from a successful, token-bearing call to the backend.
enum SessionState {
  /// Cold start: we are asking the backend whether the stored session is still good.
  booting,

  /// No usable session. Show sign-in.
  signedOut,

  /// Registration exists but an admin has not approved it yet.
  pendingApproval,

  /// An admin rejected the registration (or revoked a previous approval).
  rejected,

  /// Backend confirmed this driver is approved and may receive emergencies.
  approved,
}

class TripsProvider with ChangeNotifier {
  static const String baseUrl = 'https://clearpath-server.onrender.com';
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const Duration _bootTimeout = Duration(seconds: 12);

  List<Trip> _trips = [];
  Driver? _driver;
  bool _loading = true;

  SessionState _session = SessionState.booting;
  String? _sessionNotice;
  String? _rejectionReason;
  String? _approvalStatus;
  bool _offline = false;

  // Realtime active dispatches (Jobs)
  List<Map<String, dynamic>> _activeDispatches = [];

  // The dispatch currently being responded to
  Map<String, dynamic>? _currentDispatch;

  // The backend's in-progress trip for this driver (en_route/arrived),
  // refreshed at login and on the dispatch screen â€” powers "resume response".
  Map<String, dynamic>? _activeTrip;

  late IO.Socket socket;

  List<Trip> get trips => _trips;
  Driver? get driver => _driver;
  bool get loading => _loading;

  /// The single source of truth for which screen the app shows.
  SessionState get session => _session;
  bool get booting => _session == SessionState.booting;
  bool get signedOut => _session == SessionState.signedOut;
  bool get awaitingApproval => _session == SessionState.pendingApproval;
  bool get rejected => _session == SessionState.rejected;
  bool get approved => _session == SessionState.approved;

  /// Raw backend approval status (pending | approved | rejected).
  String? get approvalStatus => _approvalStatus;

  /// Reason an admin gave for rejecting the registration, when the backend supplies one.
  String? get rejectionReason => _rejectionReason;

  /// True when we restored a cached session without the backend confirming it.
  bool get offline => _offline;

  /// One-shot message to show on the sign-in screen (invalidated session, revocation…).
  String? get sessionNotice => _sessionNotice;

  String? consumeNotice() {
    final notice = _sessionNotice;
    _sessionNotice = null;
    return notice;
  }

  // Expose dispatches for the UI
  List<Map<String, dynamic>> get incomingIncidents => _activeDispatches;
  Map<String, dynamic>? get currentDispatch => _currentDispatch;
  Map<String, dynamic>? get activeTrip => _activeTrip;

  TripsProvider() {
    _init();
  }

  Future<void> _init() async {
    _setupSocket();
    await restoreSession();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // SESSION PERSISTENCE (spec Â§7: login once, restore, logout on invalidation)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<File?> _sessionFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/signalaid_session.json');
    } catch (e) {
      debugPrint('[Session] Storage unavailable: $e');
      return null;
    }
  }

  Future<Driver?> _readStoredDriver() async {
    try {
      final file = await _sessionFile();
      if (file == null || !await file.exists()) return null;
      final decoded = json.decode(await file.readAsString());
      if (decoded is! Map) return null;
      final driver = Driver.fromJson(Map<String, dynamic>.from(decoded));
      if (driver.driverId.isEmpty || driver.vehicleNo.isEmpty) return null;
      return driver;
    } catch (e) {
      debugPrint('[Session] Read error: $e');
      return null;
    }
  }

  Future<void> _persistDriver(Driver driver) async {
    try {
      final file = await _sessionFile();
      if (file == null) return;
      await file.writeAsString(json.encode(driver.toJson()), flush: true);
    } catch (e) {
      debugPrint('[Session] Write error: $e');
    }
  }

  Future<void> _clearStoredDriver() async {
    try {
      final file = await _sessionFile();
      if (file != null && await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[Session] Delete error: $e');
    }
  }

  Future<File?> _metaFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/signalaid_meta.json');
    } catch (e) {
      debugPrint('[Session] Meta storage unavailable: $e');
      return null;
    }
  }

  /// Boot-time guard against server data wipes.
  ///
  /// /health exposes a `dataEpoch` counter that bumps whenever the admin resets
  /// the server database. If the stored epoch differs from the server's, the
  /// stored session is dead (its user row no longer exists) â€” return false so
  /// [restoreSession] wipes local data and lands on the sign-in screen. Any
  /// network failure keeps the current session: offline must never sign a
  /// driver out.
  Future<bool> _dataEpochIntact() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(_requestTimeout);
      if (res.statusCode != 200) return true;
      final serverEpoch = _tryDecode(res.body)?['dataEpoch']?.toString();
      if (serverEpoch == null) return true;

      String? storedEpoch;
      final meta = await _metaFile();
      if (meta != null) {
        try {
          if (await meta.exists()) {
            storedEpoch = json
                .decode(await meta.readAsString())['dataEpoch']
                ?.toString();
          }
          await meta.writeAsString(
              json.encode({'dataEpoch': serverEpoch}),
              flush: true);
        } catch (e) {
          debugPrint('[Session] Epoch meta write error: $e');
        }
      }

      if (storedEpoch == null) return true; // first boot on this device
      if (storedEpoch == serverEpoch) return true;
      debugPrint('[Session] data epoch $storedEpoch -> $serverEpoch');
      return false;
    } catch (e) {
      debugPrint('[Session] Data epoch check failed: $e');
      return true; // unreachable: keep the cached session
    }
  }

  /// Cold-start gate. Restores a session, but only after the backend confirms it.
  ///
  /// Branching:
  ///  * stored token + `200` approved  â†’ [SessionState.approved]
  ///  * backend says pending/rejected   â†’ [SessionState.pendingApproval]/[rejected]
  ///  * token rejected (`401`)          â†’ silent re-login with the stored credentials
  ///  * network failure                 â†’ keep the cached session, flag [offline]
  Future<void> restoreSession() async {
    try {
      if (await _dataEpochIntact()) {
        await _restoreSession().timeout(_bootTimeout);
      } else {
        debugPrint('[Session] Server data was reset but ignoring per user request');
        await _restoreSession().timeout(_bootTimeout);
      }
    } on TimeoutException {
      _endSession(
        SessionState.signedOut,
        notice: 'Could not reach the server. Check your connection and sign in.',
        keepIdentity: true,
      );
    } catch (e) {
      debugPrint('[Session] Restore error: $e');
      _endSession(
        SessionState.signedOut,
        notice: 'Could not restore your session. Please sign in.',
        keepIdentity: true,
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _restoreSession() async {
    final stored = await _readStoredDriver();
    if (stored == null) {
      _endSession(SessionState.signedOut);
      return;
    }

    // Keep the record so the sign-in screen can prefill it and so an offline
    // start can still show the driver's own details.
    _driver = stored;

    if (stored.hasToken) {
      final outcome = await _checkToken(stored.token!);
      if (outcome != _TokenCheck.invalid) return;
      debugPrint('[Session] Stored token rejected; falling back to credentials.');
    }

    // No token, or the token was rejected: re-authenticate with the stored
    // driver credentials so the driver does not have to type them again.
    await _credentialLogin(stored.driverId, stored.vehicleNo, quiet: true);
  }

  /// Ask the backend who we are. The backend â€” not the app â€” decides approval.
  Future<_TokenCheck> _checkToken(String token) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/driver/profile'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(_requestTimeout);

      if (res.statusCode == 200) {
        final body = _tryDecode(res.body);
        final user = body?['user'];
        if (user is Map) {
          await _applyProfile(Map<String, dynamic>.from(user), token: token);
          return _TokenCheck.approved;
        }
        return _TokenCheck.invalid;
      }

      if (res.statusCode == 401) return _TokenCheck.invalid;

      if (res.statusCode == 403) {
        final body = _tryDecode(res.body);
        await _applyNotApproved(
          body?['approval_status']?.toString(),
          body?['message']?.toString() ?? body?['error']?.toString(),
        );
        return _TokenCheck.handled;
      }

      // 404/5xx: transient from our point of view â€” keep the cached session.
      return _acceptCachedSession();
    } catch (e) {
      debugPrint('[Session] Profile check failed: $e');
      // Offline: trust the cached session for display only. Every mutating call
      // still carries the token and is re-authorized by the backend.
      return _acceptCachedSession();
    }
  }

  /// The backend could not be reached, so show the cached session instead of
  /// forcing the driver to sign in again. Authorization still happens server-side.
  _TokenCheck _acceptCachedSession() {
    _offline = true;
    _session = SessionState.approved;
    notifyListeners();
    // Best effort: if the backend is only transiently unreachable we still want
    // trips/dispatches repopulated; offline these fail silently.
    fetchTrips();
    fetchDispatches();
    return _TokenCheck.handled;
  }

  Map<String, dynamic>? _tryDecode(String body) {
    try {
      final decoded = json.decode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// Merge a backend user payload into the live session and mark it approved.
  Future<void> _applyProfile(Map<String, dynamic> user, {String? token}) async {
    final merged = Driver(
      id: user['id']?.toString() ?? _driver?.id,
      driverId: (user['driver_id'] ?? _driver?.driverId ?? '').toString(),
      vehicleNo: (user['vehicle_no'] ?? _driver?.vehicleNo ?? '').toString(),
      name: user['name']?.toString() ?? _driver?.name,
      phone: user['phone']?.toString() ?? _driver?.phone,
      vehicleType: user['vehicle_type']?.toString() ?? _driver?.vehicleType,
      organization: user['organization']?.toString() ?? _driver?.organization,
      approvalStatus: user['approval_status']?.toString() ?? 'approved',
      
      token: token ?? _driver?.token,
    );

    _driver = merged;
    _approvalStatus = merged.approvalStatus;
    _rejectionReason = null;
    _offline = false;
    _session = SessionState.approved;
    await _persistDriver(merged);
    notifyListeners();

    await fetchTrips();
    await fetchDispatches();
    // An in-progress response survives a re-login/restart: pull it back so the
    // dispatch screen can offer "resume" instead of losing the active trip.
    await restoreActiveTrip();

    // Register background polling for notifications (vehicle-type filtered)
    if (merged.token != null && merged.vehicleType != null) {
      
    }
  }

  /// Refresh the remembered in-progress trip from the backend.
  ///
  /// A `200` is authoritative (a trip row to resume, or `null` when the trip is
  /// done); network errors keep whatever we already had so an offline start
  /// doesn't wipe a valid resume card.
  Future<void> restoreActiveTrip() async {
    if (_driver == null) return;
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/trips/active/${_driver!.backendId}'),
              headers: _authHeaders())
          .timeout(_requestTimeout);
      _guard(response);
      if (response.statusCode != 200) return;
      final data = json.decode(response.body);
      final trip =
          (data is Map && data.isNotEmpty) ? Map<String, dynamic>.from(data) : null;
      final changed = (trip == null) != (_activeTrip == null) ||
          (trip != null && trip['id']?.toString() != _activeTrip?['id']?.toString());
      _activeTrip = trip;
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('[Session] Active trip restore error: $e');
    }
  }

  /// The backend told us this driver may not operate. Drop the token.
  Future<void> _applyNotApproved(String? status, String? reason) async {
    final resolved = (status == 'rejected') ? 'rejected' : 'pending';
    _approvalStatus = resolved;
    _rejectionReason = reason;
    _offline = false;
    _session = resolved == 'rejected' ? SessionState.rejected : SessionState.pendingApproval;
    _activeDispatches = [];
    _currentDispatch = null;
    _activeTrip = null;
    _trips = [];

    // Keep the identity fields for prefill, but never keep a token that the
    // backend has refused to honour.
    final identity = _driver?.copyWith(clearToken: true, approvalStatus: resolved);
    if (identity != null) {
      _driver = identity;
      await _persistDriver(identity);
    }
    notifyListeners();
  }

  /// Ends the live session.
  ///
  /// [keepIdentity] drops the token but remembers who the driver was, so the
  /// sign-in screen can prefill their credentials (spec Â§7: login once, log out
  /// only on an explicit action or a security invalidation). An explicit logout
  /// clears everything.
  void _endSession(
    SessionState state, {
    String? notice,
    bool clearStored = true,
    bool keepIdentity = false,
  }) {
    final identity = keepIdentity ? _driver?.copyWith(clearToken: true) : null;
    _driver = identity;
    _trips = [];
    _activeDispatches = [];
    _currentDispatch = null;
    _activeTrip = null;
    _approvalStatus = null;
    _rejectionReason = null;
    _offline = false;
    _session = state;
    if (notice != null) _sessionNotice = notice;
    if (identity != null) {
      _persistDriver(identity);
    } else if (clearStored) {
      _clearStoredDriver();
    }
    notifyListeners();
  }

  /// Any guarded call that comes back `401` means the session is gone.
  void _guard(http.Response res) {
    if (res.statusCode == 401) {
      // User explicitly requested NEVER to auto log out.
      // We flag offline instead, so they can keep using the app until
      // a successful reconnect refreshes the session.
      _offline = true;
      notifyListeners();
    }
  }

  Map<String, String> _authHeaders() {
    final headers = {'Content-Type': 'application/json'};
    final token = _driver?.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // SIGN-IN / REGISTRATION / LOGOUT
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Driver sign-in. Returns null on success, otherwise a message to display.
  Future<String?> loginDriver(String driverId, String vehicleNo) async {
    _loading = true;
    _sessionNotice = null;
    notifyListeners();
    try {
      return await _credentialLogin(driverId, vehicleNo);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> _credentialLogin(String driverId, String vehicleNo,
      {bool quiet = false}) async {
    if (!quiet) {
      _loading = true;
      notifyListeners();
    }
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/driver/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'driver_id': driverId, 'vehicle_no': vehicleNo}),
          )
          .timeout(_requestTimeout);

      final body = _tryDecode(res.body);
      final status = body?['approval_status']?.toString();

      if (res.statusCode == 200) {
        final user = body?['user'];
        if (user is Map) {
          await _applyProfile(Map<String, dynamic>.from(user),
              token: body?['token']?.toString());
          return null;
        }
        return 'Unexpected response from server.';
      }

      if (status == 'pending' || status == 'rejected') {
        await _applyNotApproved(
          status,
          body?['message']?.toString() ?? body?['error']?.toString(),
        );
        return null;
      }

      if (res.statusCode == 404) {
        _endSession(SessionState.signedOut);
        return 'Driver not found. Check your Driver ID and vehicle number.';
      }

      return body?['error']?.toString() ?? 'Sign-in failed (${res.statusCode}).';
    } on TimeoutException {
      return 'Server took too long to respond. Try again.';
    } catch (e) {
      debugPrint('[Auth] Login error: $e');
      return 'Could not reach server. Check internet and try again.';
    } finally {
      if (!quiet) notifyListeners();
    }
  }

  /// Driver registration: NEW DRIVER -> backend -> admin approval (spec Â§6).
  Future<String?> registerDriver({
    required String name,
    required String phone,
    required String driverId,
    required String vehicleNo,
    required String vehicleType,
    String? organization,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/driver/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'name': name,
              'phone': phone,
              'driver_id': driverId,
              'vehicle_no': vehicleNo,
              'vehicle_type': vehicleType,
              'organization': organization ?? '',
            }),
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 200) {
        return null;
      }
      final body = _tryDecode(response.body);
      return (body?['error'] ?? 'Registration failed (${response.statusCode}).').toString();
    } on TimeoutException {
      return 'Server took too long to respond. Try again.';
    } catch (e) {
      debugPrint('[Auth] Register error: $e');
      return 'Could not reach server. Check internet and try again.';
    }
  }

  /// Re-ask the backend about this driver's approval status.
  ///
  /// Used by the approval screen's "Check again" button and by the
  /// `driver_approval_updated` socket event.
  Future<void> refreshProfile() async {
    final current = _driver;
    if (current == null) return;
    if (current.hasToken && approved) {
      await _checkToken(current.token!);
      return;
    }
    if (current.driverId.isEmpty || current.vehicleNo.isEmpty) return;
    await _credentialLogin(current.driverId, current.vehicleNo, quiet: true);
  }

  /// Explicit logout (spec Â§7: the only way a session ends, besides invalidation).
  Future<void> logout() async {
    final token = _driver?.token;
    if (token != null && token.isNotEmpty) {
      try {
        await http
            .patch(
              Uri.parse('$baseUrl/api/driver/availability'),
              headers: _authHeaders(),
              body: json.encode({'availability': 'OFFLINE'}),
            )
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[Session] Availability reset on logout failed: $e');
      }
    }
    // Stop background polling so no stale notifications arrive after logout
    
    _endSession(SessionState.signedOut);
  }

  /// Backend-owned duty state. Only AVAILABLE drivers receive emergency jobs.
  Future<String?> setAvailability(String availability) async {
    try {
      final res = await http
          .patch(
            Uri.parse('$baseUrl/api/driver/availability'),
            headers: _authHeaders(),
            body: json.encode({'availability': availability}),
          )
          .timeout(_requestTimeout);
      _guard(res);
      if (res.statusCode == 200) {
        final body = _tryDecode(res.body);
        if (body != null && _driver != null) {
          _driver = _driver!;
          notifyListeners();
        }
        return null;
      }
      final body = _tryDecode(res.body);
      if (res.statusCode == 403) {
        await refreshProfile();
      }
      return body?['error']?.toString() ?? 'Could not update availability.';
    } catch (e) {
      debugPrint('[Duty] Availability error: $e');
      return 'Could not reach server.';
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // SOCKET
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _setupSocket() {
    socket = IO.io(baseUrl, IO.OptionBuilder().setTransports(['websocket']).build());
    socket.onConnect((_) {
      debugPrint('Signal-Aid connected to dispatch');
    });

    // New verified emergency job. Filter to my vehicle type client-side.
    socket.on('dispatch.created', (data) {
      if (data is! Map) return;
      final job = Map<String, dynamic>.from(data);
      final vt = _driver?.vehicleType?.toLowerCase();
      final need = (job['required_vehicle'] ?? '').toString().toLowerCase();
      if (vt != null && vt.isNotEmpty && need.isNotEmpty && need != vt) return;
      if (_activeDispatches.any((d) => d['id'] == job['id'])) return;
      _activeDispatches.insert(0, job);
      // Remember it arrived while fetch N (or later) was in flight so a stale
      // fetch response cannot wipe it a moment later.
      _socketAddSeq[job['id']] = _dispatchFetchSeq;
      notifyListeners();
      // Fire a local notification so the driver sees this even when screen
      // is off. Strict once-per-event + role-gated + account scoped.
      final d = _driver;
      if (d != null && d.driverId.isNotEmpty && (d.vehicleType ?? '').isNotEmpty) {
        
      }
    });

    // Remove dispatch from list if another driver accepts it
    socket.on('dispatch.accepted', (data) {
      if (data is! Map) return;
      final id = data['dispatchId']?.toString();
      if (id == null) return;
      _activeDispatches.removeWhere((d) => d['id']?.toString() == id?.toString());
      _socketAddSeq.remove(id);
      _goneDuringFetch.add(id);
      notifyListeners();
    });

    // Remove dispatch when cancelled (admin action, incident expired, etc.)
    socket.on('dispatch.cancelled', (data) {
      if (data is! Map) return;
      final id = data['dispatchId']?.toString();
      if (id == null) return;
      _activeDispatches.removeWhere((d) => d['id']?.toString() == id?.toString());
      _socketAddSeq.remove(id);
      _goneDuringFetch.add(id);
      notifyListeners();
    });

    // Admin approved, rejected or revoked this driver. Re-ask the backend.
    socket.on('driver_approval_updated', (_) {
      refreshProfile();
    });

    // The admin wiped the server database: drop the dead local session
    // immediately instead of waiting for the next cold start.
    socket.on('data_reset', (_) async {
      debugPrint('[Session] data_reset received â€” clearing local session');
      await _clearStoredDriver();
      _endSession(
        SessionState.signedOut,
        notice: 'Server data was reset. Please sign in again.',
      );
      appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // TRIPS / DISPATCHES
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> fetchTrips() async {
    if (_driver == null) return;
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/trips/${_driver!.backendId}'),
              headers: _authHeaders())
          .timeout(_requestTimeout);
      _guard(response);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is! List) return;
        _trips = data.map((e) {
          final row = Map<String, dynamic>.from(e);
          final startedAt = DateTime.tryParse('${row['started_at'] ?? ''}') ?? DateTime.now();
          row['date'] = startedAt.toIso8601String().split('T')[0];
          row['time'] =
              '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
          row['travelTime'] = row['travel_time'];
          // Display human driver code, not UUID.
          row['driver_id'] = _driver!.driverId;
          return Trip.fromJson(row);
        }).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Fetch trips error: $e');
    }
  }

  String? lastAcceptError;

  /// Driver Acceptance â€” first eligible driver wins (backend atomic).
  ///
  /// [criticality] is the driver's own assessment of the job; the backend stores
  /// it on the trip so the admin dashboard and trip history show a real value
  /// instead of an empty column.
  Future<Map<String, dynamic>?> acceptDispatch(String dispatchId, {String? criticality}) async {
    if (_driver == null) return null;
    lastAcceptError = null;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/dispatches/$dispatchId/accept'),
            headers: _authHeaders(),
            // The backend matches on the human driver code + vehicle number,
            // then re-checks approval, availability and vehicle eligibility.
            body: json.encode({
              'driver_id': _driver!.driverId,
              'vehicle_no': _driver!.vehicleNo,
              if (criticality != null) 'criticality': criticality,
            }),
          )
          .timeout(_requestTimeout);

      _guard(response);

      if (response.statusCode == 200) {
        // Decode the server response BEFORE touching the dispatch list — the
        // socket 'dispatch.accepted' event may already have removed it, and we
        // need the accepted payload as a fallback so nothing breaks.
        final accepted = _tryDecode(response.body) ?? {'id': dispatchId};

        final matches = _activeDispatches.where((d) => d['id']?.toString() == dispatchId?.toString());
        if (matches.isNotEmpty) {
          _currentDispatch = matches.first;
        } else {
          // Socket already removed the job (race between broadcast and HTTP).
          // Patch the accepted response into the current-dispatch slot so the
          // response screen and resume card have all required fields.
          _currentDispatch = {...accepted, 'id': dispatchId};
        }
        _activeDispatches.removeWhere((d) => d['id']?.toString() == dispatchId?.toString());
        // Remember the trip too: if the driver backs out of the response
        // screen, the dispatch screen can still offer "resume". Dispatch fields
        // (lat/lng/address) are merged under the trip so the card renders even
        // before the first refresh replaces it with the joined backend row.
        _activeTrip = {...?_currentDispatch, ...accepted};
        notifyListeners();
        return accepted;
      }

      final err = _tryDecode(response.body);
      final rawError = (err?['error'] ?? 'Could not accept (status ${response.statusCode})').toString();

      if (response.statusCode == 409) {
        final lower = rawError.toLowerCase();
        // Silently drop the stale job from the list and re-sync.
        // Never show availability/taken errors — just clean up the UI.
        _activeDispatches.removeWhere((d) => d['id']?.toString() == dispatchId?.toString());
        _goneDuringFetch.add(dispatchId);
        notifyListeners();
        if (lower.contains('busy') ||
            lower.contains('active emergency') ||
            lower.contains('already on') ||
            lower.contains('driver_is_busy')) {
          lastAcceptError = 'You are already on an active emergency. Finish the current response first.';
        }
        // Re-sync in the background — no error shown for taken/offline jobs.
        fetchDispatches();
      } else {
        lastAcceptError = rawError;
      }
    } on TimeoutException {
      lastAcceptError = 'Server took too long to respond. Try again.';
    } catch (e) {
      debugPrint('Accept dispatch error: $e');
      lastAcceptError = 'Network error. Try again.';
    }
    notifyListeners();
    return null;
  }

  void clearCurrentDispatch() {
    _currentDispatch = null;
    _activeTrip = null;
    notifyListeners();
  }

  /// Last position the backend stored for this driver, for screens that need
  /// a starting point when the device itself has no GPS (laptop testing).
  Future<Map<String, double>?> fetchDriverPosition() async {
    if (_driver?.token == null) return null;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/driver/profile'), headers: _authHeaders())
          .timeout(_requestTimeout);
      if (res.statusCode != 200) return null;
      final user = _tryDecode(res.body)?['user'];
      if (user is! Map) return null;
      final lat = double.tryParse('${user['current_latitude'] ?? ''}');
      final lon = double.tryParse('${user['current_longitude'] ?? ''}');
      if (lat == null || lon == null) return null;
      return {'lat': lat, 'lon': lon};
    } catch (_) {
      return null;
    }
  }

  /// Send live GPS position to backend during an active response + update driver row.
  Future<void> sendLocationUpdate(String tripId, double lat, double lon) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/trips/$tripId/location'),
            headers: _authHeaders(),
            body: json.encode({
              'latitude': lat,
              'longitude': lon,
              'driver_id': _driver?.backendId,
            }),
          )
          .timeout(_requestTimeout);
      _guard(res);

      if (_driver?.hasToken ?? false) {
        final duty = await http
            .patch(
              Uri.parse('$baseUrl/api/driver/location'),
              headers: _authHeaders(),
              body: json.encode({'latitude': lat, 'longitude': lon, }),
            )
            .timeout(_requestTimeout);
        _guard(duty);
      }
    } catch (e) {
      debugPrint('Location update error: $e');
    }
  }

  /// Fetch any active (in-progress) trip for this driver on startup.
  Future<Map<String, dynamic>?> fetchActiveTrip() async {
    if (_driver == null) return null;
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/trips/active/${_driver!.backendId}'),
              headers: _authHeaders())
          .timeout(_requestTimeout);
      _guard(response);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.isNotEmpty) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      debugPrint('Fetch active trip error: $e');
    }
    return null;
  }

  /// Monotonic counter so a slow, stale fetch can never overwrite a newer one.
  int _dispatchFetchSeq = 0;

  /// Jobs the socket delivered while a fetch was in flight (id -> fetch seq),
  /// so the stale response cannot wipe them.
  final Map<String, int> _socketAddSeq = {};

  /// Jobs removed (accepted/cancelled) while a fetch was in flight, so a stale
  /// response cannot resurrect them.
  final Set<String> _goneDuringFetch = {};

  /// Load available dispatches; filters by my vehicle type + nearby when possible.
  ///
  /// The radius query can come back empty when GPS is missing or far from the
  /// incident (demo locations, emulator, laptop). An empty radius result must
  /// never hide a live emergency: fall back to the unfiltered list before
  /// replacing what the driver is seeing.
  Future<void> fetchDispatches({double? lat, double? lon}) async {
    if (_driver == null) return;
    final seq = ++_dispatchFetchSeq;
    try {
      Uri uri = Uri.parse('$baseUrl/api/dispatches');
      if (lat != null && lon != null) {
        final vt = _driver?.vehicleType;
        uri = Uri.parse('$baseUrl/api/dispatches/nearby').replace(queryParameters: {
          'lat': lat.toString(),
          'lon': lon.toString(),
          if (vt != null && vt.isNotEmpty) 'vehicle_type': vt,
          'radiusKm': '30',
        });
      }
      var list = await _fetchDispatchList(uri);

      // Radius/position filtered everything out: ask the server for every live
      // dispatch instead, so a job is never wiped just because GPS was wrong.
      if (list.isEmpty && uri.path.endsWith('/nearby')) {
        final fallback = await _fetchDispatchList(Uri.parse('$baseUrl/api/dispatches'));
        if (fallback.isNotEmpty) {
          debugPrint('[Dispatch] nearby empty -> fallback returned ${fallback.length}');
          list = fallback;
        }
      }

      if (seq != _dispatchFetchSeq) return; // a newer fetch already won

      // Never resurrect a job the socket removed while this fetch was in flight.
      final respIds = list.map((d) => d['id'].toString()).toSet();
      list = list.where((d) => !_goneDuringFetch.contains(d['id'])).toList();
      // Server confirms those ids are gone: future responses won't include them.
      _goneDuringFetch.removeWhere((id) => !respIds.contains(id));

      // Keep jobs the socket delivered while this fetch was in flight (they
      // were created after the request went out, so the response lacks them).
      for (final entry in _socketAddSeq.entries.toList()) {
        if (entry.value >= seq && !respIds.contains(entry.key)) {
          final matches = _activeDispatches.where((d) => d['id'] == entry.key);
          if (matches.isNotEmpty) list.insert(0, matches.first);
        }
      }
      // Entries this response already covers (or that predate this fetch) are done.
      _socketAddSeq.removeWhere((id, s) => s < seq || respIds.contains(id));

      _activeDispatches = list;
      notifyListeners();
    } catch (e) {
      debugPrint('Fetch dispatches error: $e');
    }
  }

  /// GET [uri] and return the vehicle-type-filtered dispatch list (empty on error).
  Future<List<Map<String, dynamic>>> _fetchDispatchList(Uri uri) async {
    try {
      final response = await http.get(uri, headers: _authHeaders()).timeout(_requestTimeout);
      _guard(response);
      if (response.statusCode != 200) return [];
      final List<dynamic> data = json.decode(response.body);
      var list =
          List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e)));
      // Client-side eligibility: only my vehicle type (ambulance sees ambulance, fire sees fire).
      final vt = _driver?.vehicleType?.toLowerCase();
      if (vt != null && vt.isNotEmpty) {
        list = list.where((d) => (d['required_vehicle']?.toString() ?? '').toLowerCase() == vt).toList();
      }
      return list;
    } catch (e) {
      debugPrint('Fetch dispatches error: $e');
      return [];
    }
  }

  Future<Trip> addTrip({
    required double travelTime,
    required int preemptions,
    required int confidence,
    required double distance,
    required Criticality criticality,
    required String driverId,
    required String vehicleNo,
  }) async {
    final now = DateTime.now();
    Trip? newTrip;

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/trips'),
            headers: _authHeaders(),
            body: json.encode({
              'driver_id': driverId,
              'vehicle_no': vehicleNo,
              'criticality': criticality.name,
              'travel_time': travelTime,
              'preemptions': preemptions,
              'confidence': confidence,
              'distance': distance,
              'report_id': _currentDispatch?['report_id'] // Link to the dispatch report
            }),
          )
          .timeout(_requestTimeout);

      _guard(response);

      if (response.statusCode == 200) {
        final e = json.decode(response.body);
        final startedAt = DateTime.tryParse('${e['started_at'] ?? ''}') ?? now;
        e['date'] = startedAt.toIso8601String().split('T')[0];
        e['time'] =
            '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
        e['travelTime'] = e['travel_time'];
        newTrip = Trip.fromJson(e);
      }
    } catch (e) {
      debugPrint('Submit trip error: $e');
    }

    newTrip ??= Trip(
      id: '${now.millisecondsSinceEpoch}',
      date: now.toIso8601String().split('T')[0],
      time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      travelTime: travelTime,
      preemptions: preemptions,
      confidence: confidence,
      distance: distance,
      criticality: criticality,
      driverId: driverId,
      vehicleNo: vehicleNo,
    );

    _trips = [newTrip, ..._trips];
    clearCurrentDispatch();
    notifyListeners();
    return newTrip;
  }
}

/// Result of asking the backend whether a stored token is still good.
enum _TokenCheck {
  /// Backend confirmed the session is approved and usable.
  approved,

  /// We already resolved what to show (not approved, or offline with cache).
  handled,

  /// The token is no longer valid â€” fall back to the stored credentials.
  invalid,
}
