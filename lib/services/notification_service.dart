import 'dart:convert';
import 'dart:ui';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Alarm ID used for the repeating background poll.
// Must be a stable integer — never change it across app versions.
// ---------------------------------------------------------------------------
const int _kAlarmId = 7842;

// ---------------------------------------------------------------------------
// Background callback — top-level, never inside a class.
// AlarmManager wakes the app and calls this even when it is killed.
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _alarmCallback() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final driverId = prefs.getString('notif_driver_id');
    final vehicleType = prefs.getString('notif_vehicle_type');
    final token = prefs.getString('notif_token');
    if (driverId == null || vehicleType == null || token == null) return;

    final seenKey = _seenIdsKeyFor(driverId);
    const baseUrl = 'https://clearpath-server.onrender.com';
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/dispatches'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return;
    final List<dynamic> dispatches = json.decode(response.body);

    final seenRaw = prefs.getStringList(seenKey) ?? [];
    final seen = seenRaw.toSet();
    final matchTypes = _matchingTypes(vehicleType);

    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: android));

    // Create the notification channel (required on Android 8+)
    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationService.channelId,
        NotificationService.channelName,
        description: NotificationService.channelDesc,
        importance: Importance.max,
      ),
    );

    int notifId = 100;
    final newSeen = <String>{...seen};

    for (final d in dispatches) {
      final id = d['id']?.toString();
      if (id == null) continue;
      newSeen.add(id);
      if (seen.contains(id)) continue; // already notified — once-per-event

      // Dual role check: vehicle type on the incident AND its emergency type.
      final requiredVehicle = (d['required_vehicle'] ?? '')
          .toString()
          .toLowerCase();
      final type = (d['type'] ?? '').toString().toLowerCase();
      if (requiredVehicle.isNotEmpty &&
          requiredVehicle != vehicleType.toLowerCase()) {
        continue;
      }
      if (!matchTypes.contains(type)) continue;

      final address = d['address']?.toString() ?? 'Unknown location';
      final description = d['description']?.toString() ?? '';

      await plugin.show(
        notifId++,
        '🚨 ${_prettyType(type)} Emergency',
        '$address${description.isNotEmpty ? ' — $description' : ''}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            NotificationService.channelId,
            NotificationService.channelName,
            channelDescription: NotificationService.channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: Color(0xFFEF4444),
            enableVibration: true,
            playSound: true,
            autoCancel: true,
          ),
        ),
      );
    }

    // Persist seen IDs (capped at 200) — account-scoped key
    final trimmed = newSeen.toList();
    if (trimmed.length > 200) trimmed.removeRange(0, trimmed.length - 200);
    await prefs.setStringList(seenKey, trimmed);
  } catch (e) {
    debugPrint('[Notif BG] $e');
  }
}

/// Returns the SharedPreferences key used to track seen dispatch IDs for the
/// currently signed-in driver. Keeping one slot per driverId guarantees the
/// notification state is tied to the user ACCOUNT, not the physical device.
String _seenIdsKeyFor(String driverId) => 'notif_seen_ids_$driverId';

Set<String> _matchingTypes(String vehicleType) {
  switch (vehicleType.toLowerCase()) {
    case 'fire':
      return {'fire'};
    case 'ambulance':
      return {'accident'};
    case 'police':
      return {'accident', 'congestion', 'blocked'};
    default:
      return {'fire', 'accident', 'congestion', 'blocked', 'flooding'};
  }
}

String _prettyType(String type) {
  switch (type) {
    case 'fire':
      return 'Fire';
    case 'accident':
      return 'Accident';
    case 'congestion':
      return 'Congestion';
    case 'blocked':
      return 'Road Blocked';
    case 'flooding':
      return 'Flooding';
    default:
      return type.isNotEmpty ? type[0].toUpperCase() + type.substring(1) : type;
  }
}

// ---------------------------------------------------------------------------
// NotificationService — singleton for in-app use
// ---------------------------------------------------------------------------
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String channelId = 'signalaid_emergency';
  static const String channelName = 'Emergency Dispatches';
  static const String channelDesc =
      'Alerts for fire and accident emergency dispatches';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Init ────────────────────────────────────────────────────────────────
  /// Call once in main() before runApp.
  Future<void> init() async {
    if (_initialized) return;

    // Initialize AlarmManager
    await AndroidAlarmManager.initialize();

    // Initialize local notifications plugin
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onTap,
    );

    // Create the notification channel
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDesc,
            importance: Importance.max,
          ),
        );

    // Request Android 13+ notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _initialized = true;
    debugPrint('[Notif] Initialized.');
  }

  // ── Start polling ────────────────────────────────────────────────────────
  /// Call after a successful login. Saves credentials and schedules a
  /// repeating alarm that fires every 15 minutes — even when app is killed.
  /// The seen-ID tracker is scoped to this driverId, so a different user
  /// logging in on the same physical device gets a clean, independent dedup
  /// set — notifications are tied strictly to the logged-in ACCOUNT.
  Future<void> startPolling({
    required String driverId,
    required String vehicleType,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_driver_id', driverId);
    await prefs.setString('notif_vehicle_type', vehicleType);
    await prefs.setString('notif_token', token);
    // Fresh per-account seen-ID set on every login → new events seen first time
    await prefs.setStringList(_seenIdsKeyFor(driverId), []);

    // Cancel any previous alarm and schedule a new one
    await AndroidAlarmManager.cancel(_kAlarmId);
    await AndroidAlarmManager.periodic(
      const Duration(minutes: 15),
      _kAlarmId,
      _alarmCallback,
      wakeup: true, // wake the CPU from sleep
      rescheduleOnReboot: true, // survive device restart
      exact: false, // inexact is fine and uses less battery
    );

    debugPrint('[Notif] Alarm polling started — $vehicleType / $driverId');
  }

  // ── Stop polling ─────────────────────────────────────────────────────────
  /// Call on explicit logout.
  Future<void> stopPolling() async {
    await AndroidAlarmManager.cancel(_kAlarmId);
    final prefs = await SharedPreferences.getInstance();
    final driverId = prefs.getString('notif_driver_id');
    await prefs.remove('notif_driver_id');
    await prefs.remove('notif_vehicle_type');
    await prefs.remove('notif_token');
    // Wipe the per-account seen set on logout (privacy + clean state for next
    // driver who signs in on this device)
    if (driverId != null) await prefs.remove(_seenIdsKeyFor(driverId));
    debugPrint('[Notif] Alarm polling stopped.');
  }

  // ── Once-per-event dedup helper (account scoped) ─────────────────────────
  /// Returns true when this dispatch has NEVER been shown to the signed-in
  /// driver. False = duplicate; caller MUST skip. Atomically marks it seen.
  Future<bool> _shouldNotifyAndMarkSeen(
    String driverId,
    String dispatchId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _seenIdsKeyFor(driverId);
    final seen = (prefs.getStringList(key) ?? []).toSet();
    if (seen.contains(dispatchId)) return false;
    seen.add(dispatchId);
    final trimmed = seen.toList();
    if (trimmed.length > 200) trimmed.removeRange(0, trimmed.length - 200);
    await prefs.setStringList(key, trimmed);
    return true;
  }

  // ── Foreground notification ───────────────────────────────────────────────
  /// Called from the Socket.IO handler while the app is open.
  /// Strict role filtering: required_vehicle (from the dispatch row) AND
  /// incident dispatch.type MUST match the signed-in driver's vehicleType.
  /// Plus strict once-per-event dedup scoped to the driver account.
  Future<void> showDispatchNotification(
    Map<String, dynamic> dispatch, {
    required String driverId,
    required String driverVehicleType,
  }) async {
    if (!_initialized) return;
    final dispatchId = dispatch['id']?.toString();
    if (dispatchId == null) return;

    // 1) Strict dual-field role check — fire => fire emergency, ambulance => accident
    final type = (dispatch['type'] ?? '').toString().toLowerCase();
    final reqVehicle = (dispatch['required_vehicle'] ?? '')
        .toString()
        .toLowerCase();
    final vt = driverVehicleType.toLowerCase();
    final matchTypes = _matchingTypes(driverVehicleType);

    final roleMatch =
        matchTypes.contains(type) && (reqVehicle.isEmpty || reqVehicle == vt);
    if (!roleMatch) {
      debugPrint(
        '[Notif] Skip: role mismatch vt=$vt type=$type req=$reqVehicle',
      );
      return;
    }

    // 2) Once-per-event dedup scoped to this signed-in driver account
    final show = await _shouldNotifyAndMarkSeen(driverId, dispatchId);
    if (!show) {
      debugPrint(
        '[Notif] Skip: dispatch $dispatchId already seen for driver $driverId',
      );
      return;
    }

    final address = dispatch['address']?.toString() ?? 'Unknown location';
    final description = dispatch['description']?.toString() ?? '';

    await _plugin.show(
      dispatchId.hashCode.abs() % 1000,
      '🚨 ${_prettyType(type)} Emergency',
      '$address${description.isNotEmpty ? ' — $description' : ''}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Color(0xFFEF4444),
          enableVibration: true,
          playSound: true,
          autoCancel: true,
          fullScreenIntent: true,
        ),
      ),
    );
  }

  void _onTap(NotificationResponse details) {
    debugPrint('[Notif] Tapped: ${details.payload}');
  }
}
