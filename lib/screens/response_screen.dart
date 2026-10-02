import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/card.dart';
import '../widgets/primary_button.dart';
import '../widgets/stat.dart';

/// S6 — Active response.
///
/// Everything on this screen is real: the driver position comes from the device
/// GPS, the incident position comes from the backend dispatch, and the route
/// (distance, ETA and the drawn path) comes from the backend's routing provider.
/// Nothing here is estimated or invented — when a value is unknown it renders as
/// `—` instead of a plausible-looking number.
class ResponseScreen extends StatefulWidget {
  const ResponseScreen({super.key});

  @override
  State<ResponseScreen> createState() => _ResponseScreenState();
}

class _ResponseScreenState extends State<ResponseScreen> {
  final MapController _mapController = MapController();

  String? _tripId;
  Map<String, dynamic>? _dispatch;

  LatLng? _incident;
  LatLng? _driver;

  /// True when the position came from the backend's last-known fix instead of
  /// live device GPS (e.g. testing on a laptop with no GPS hardware).
  bool _usingLastKnown = false;
  bool _triedLastKnown = false;

  /// Where this emergency journey started (first GPS fix after accepting).
  /// Ambulances get a return route back here after arrival; fire vehicles don't.
  LatLng? _journeyStart;
  List<LatLng> _returnPoints = const [];
  double? _returnDistanceKm;
  int? _returnDurationMin;
  bool _loadingReturn = false;

  /// Route exactly as the backend returned it.
  List<LatLng> _routePoints = const [];
  double? _routeDistanceKm;
  int? _routeDurationMin;
  String? _routeProvider;
  bool _loadingRoute = false;
  String? _routeError;
  DateTime? _lastRouteFetch;

  /// Trip status as confirmed by the backend, never assumed locally.
  String _status = 'en_route';
  bool _arrived = false;
  bool _completing = false;

  Timer? _locationTimer;
  bool _locationDenied = false;

  /// GMaps-style follow: the camera tracks the device until the driver pans
  /// the map by hand. Recentre re-engages follow mode.
  bool _followDriver = true;

  bool _argsLoaded = false;

  @override
  void initState() {
    super.initState();
    // NOTE: ModalRoute.of(context) must NOT be called in initState.
    _startLocationUpdates();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsLoaded) return;
    _argsLoaded = true;
    _initializeData();
  }

  void _initializeData() {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    _tripId = args?['tripId'] as String?;

    final rawDispatch = args?['dispatch'];
    if (rawDispatch is Map) {
      _dispatch = Map<String, dynamic>.from(rawDispatch);
      _incident = _latLngFrom(_dispatch!['latitude'], _dispatch!['longitude']);
    }

    // Journey start passed from the dispatch screen (ambulance bay / hospital).
    // This is the anchor of the ambulance way-back leg after pickup.
    final startPos = _latLngFrom(args?['startLat'], args?['startLon']);
    if (startPos != null) _journeyStart = startPos;

    _status = (args?['status'] as String?) ?? 'en_route';
    _arrived = _status == 'arrived';
    if (mounted) setState(() {});
  }

  static LatLng? _latLngFrom(dynamic latitude, dynamic longitude) {
    final lat = double.tryParse('${latitude ?? ''}');
    final lon = double.tryParse('${longitude ?? ''}');
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  /// Live GPS: the driver position is what the map draws the route from.
  /// Falls back once to the backend's last-known fix so the screen still
  /// works where the device has no GPS hardware (laptop testing).
  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      try {
        if (!await Geolocator.isLocationServiceEnabled()) {
          await _useLastKnownPosition();
          return;
        }

        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (mounted) setState(() => _locationDenied = true);
          await _useLastKnownPosition();
          return;
        }

        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (!mounted) return;

        final moved = _driver == null ||
            (_driver!.latitude - position.latitude).abs() > 0.00005 ||
            (_driver!.longitude - position.longitude).abs() > 0.00005;
        setState(() {
          _driver = LatLng(position.latitude, position.longitude);
          _locationDenied = false;
          // Remember where the journey started for the ambulance return leg.
          _journeyStart ??= _driver;
        });
        _maybeReturnRoute();
        // Follow the device like a navigation app (unless the driver panned away).
        if (moved && _followDriver && mounted) {
          try {
            _mapController.move(_driver!, _mapController.camera.zoom);
          } catch (_) {}
        }

        // Uplink so the backend and admin dashboard track this vehicle.
        if (_tripId != null) {
          final provider = Provider.of<TripsProvider>(context, listen: false);
          await provider.sendLocationUpdate(_tripId!, position.latitude, position.longitude);
        }

        // Re-route as the driver moves, but not on every GPS tick.
        final sinceLast = _lastRouteFetch == null
            ? const Duration(days: 1)
            : DateTime.now().difference(_lastRouteFetch!);
        if (sinceLast.inSeconds >= 15) _fetchRoute();
      } catch (e) {
        debugPrint('[Response] GPS update error: $e');
        await _useLastKnownPosition();
      }
    });
  }

  /// One-time fallback to the position the backend last stored for this
  /// driver, so the route still draws without device GPS.
  Future<void> _useLastKnownPosition() async {
    if (_triedLastKnown || _driver != null || !mounted) return;
    _triedLastKnown = true;
    try {
      final provider = Provider.of<TripsProvider>(context, listen: false);
      final pos = await provider.fetchDriverPosition();
      if (pos == null || !mounted) return;
      setState(() {
        _driver = LatLng(pos['lat']!, pos['lon']!);
        _usingLastKnown = true;
        _journeyStart ??= _driver;
      });
      _fitRoute();
      _fetchRoute();
      _maybeReturnRoute();
    } catch (e) {
      debugPrint('[Response] Last-known position error: $e');
    }
  }

  /// Ask the backend for the real driving route between the driver and the incident.
  Future<void> _fetchRoute() async {
    final from = _driver;
    final to = _incident;
    if (from == null || to == null || _loadingRoute) return;

    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });

    try {
      final uri = Uri.parse('${TripsProvider.baseUrl}/api/route').replace(queryParameters: {
        'fromLat': from.latitude.toString(),
        'fromLon': from.longitude.toString(),
        'toLat': to.latitude.toString(),
        'toLon': to.longitude.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) {
        throw Exception('Routing returned ${res.statusCode}');
      }

      final body = json.decode(res.body) as Map<String, dynamic>;
      final points = <LatLng>[];
      final rawGeometry = body['geometry'];
      if (rawGeometry is List) {
        for (final pair in rawGeometry) {
          if (pair is List && pair.length >= 2) {
            points.add(LatLng(
              (pair[0] as num).toDouble(),
              (pair[1] as num).toDouble(),
            ));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _routePoints = points;
        _routeDistanceKm = (body['distanceKm'] as num?)?.toDouble();
        _routeDurationMin = (body['durationMin'] as num?)?.toInt();
        _routeProvider = body['provider']?.toString();
        _lastRouteFetch = DateTime.now();
      });
      _fitRoute();
    } catch (e) {
      debugPrint('[Response] Route fetch error: $e');
      if (mounted) setState(() => _routeError = 'Could not load the route.');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  /// Frame the whole route (driver + incident) on the map.
  void _fitRoute() {
    final points = <LatLng>[
      ..._routePoints,
      if (_driver != null) _driver!,
      if (_incident != null) _incident!,
    ];
    if (points.length < 2) return;

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(42),
        ),
      );
    } catch (e) {
      debugPrint('[Response] Could not fit map bounds: $e');
    }
  }

  /// Ambulance return journey: incident → original start location.
  /// Fire vehicles never see this section.
  Future<void> _fetchReturnRoute() async {
    final from = _incident;
    final to = _journeyStart;
    if (from == null || to == null || _loadingReturn) return;
    setState(() => _loadingReturn = true);
    try {
      final uri = Uri.parse('${TripsProvider.baseUrl}/api/route').replace(queryParameters: {
        'fromLat': from.latitude.toString(),
        'fromLon': from.longitude.toString(),
        'toLat': to.latitude.toString(),
        'toLon': to.longitude.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200 || !mounted) return;
      final body = json.decode(res.body) as Map<String, dynamic>;
      final points = <LatLng>[];
      final rawGeometry = body['geometry'];
      if (rawGeometry is List) {
        for (final pair in rawGeometry) {
          if (pair is List && pair.length >= 2) {
            points.add(LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble()));
          }
        }
      }
      setState(() {
        _returnPoints = points;
        _returnDistanceKm = (body['distanceKm'] as num?)?.toDouble();
        _returnDurationMin = (body['durationMin'] as num?)?.toInt();
      });
    } catch (e) {
      debugPrint('[Response] Return route error: $e');
    } finally {
      if (mounted) setState(() => _loadingReturn = false);
    }
  }

  /// Hand off to a real navigation provider for turn-by-turn.
  Future<void> _startNavigation() async {
    final to = _incident;
    if (to == null) {
      _snack('Incident location is not available yet.');
      return;
    }
    await _openMaps(destination: to);
  }

  /// Way-back leg for ambulances: current position (scene) → journey start.
  Future<void> _navigateBack() async {
    final to = _journeyStart;
    if (to == null) {
      _snack('Starting point is not known yet.');
      return;
    }
    await _openMaps(destination: to);
  }

  /// Open driving directions in a real navigation app.
  ///
  /// Tries, in order: Google Maps navigation intent, the universal Maps
  /// directions URL, then a plain geo: intent. `canLaunchUrl` is deliberately
  /// NOT used as a gate — on Android 11+ it returns false whenever the target
  /// app is outside the package-visibility queries, even though the launch
  /// itself would have worked, which is exactly the "Could not open
  /// navigation" failure drivers were seeing.
  Future<void> _openMaps({required LatLng destination}) async {
    final dlat = destination.latitude.toStringAsFixed(6);
    final dlon = destination.longitude.toStringAsFixed(6);
    final origin = _driver != null
        ? '&origin=${_driver!.latitude.toStringAsFixed(6)},${_driver!.longitude.toStringAsFixed(6)}'
        : '';

    final candidates = <Uri>[
      // Straight into Google Maps turn-by-turn (current position → destination).
      Uri.parse('google.navigation:q=$dlat,$dlon'),
      // Universal directions URL — opens Maps when installed, browser otherwise.
      Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$dlat,$dlon$origin&travelmode=driving'),
      // Bare geo: intent as the last resort.
      Uri.parse('geo:$dlat,$dlon?q=$dlat,$dlon'),
    ];

    for (final uri in candidates) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (e) {
        debugPrint('[Response] Navigation launch failed ($uri): $e');
      }
    }
    _snack('Could not open navigation — please install Google Maps.');
  }

  /// Fetch the ambulance return leg once both anchors are known.
  /// Guards keep it to exactly one network call per trip.
  void _maybeReturnRoute() {
    if (_incident == null ||
        _journeyStart == null ||
        _returnDistanceKm != null ||
        _loadingReturn) {
      return;
    }
    final vt = Provider.of<TripsProvider>(context, listen: false).driver?.vehicleType;
    if (vt == null || vt == 'ambulance') _fetchReturnRoute();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// PATCH the trip status; the backend owns the transition and the response is
  /// what this screen reflects. Returns true when the backend accepted it.
  Future<bool> _updateStatus(String status) async {
    if (_tripId == null) {
      _snack('No active trip to update.');
      return false;
    }

    final provider = Provider.of<TripsProvider>(context, listen: false);
    final driver = provider.driver;

    try {
      final res = await http
          .patch(
            Uri.parse('${TripsProvider.baseUrl}/api/trips/$_tripId/status'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'status': status,
              'driver_id': driver?.backendId ?? '',
            }),
          )
          .timeout(const Duration(seconds: 12));

      final body = json.decode(res.body);
      if (res.statusCode != 200) {
        _snack(body is Map ? '${body['error'] ?? 'Could not update status'}' : 'Could not update status');
        return false;
      }

      if (!mounted) return true;
      setState(() {
        _status = (body is Map ? body['status']?.toString() : null) ?? status;
        if (status == 'arrived') {
          _arrived = true;
          // Ambulances show the return leg; fire vehicles stop at the scene.
          final vt = provider.driver?.vehicleType;
          if (vt == null || vt == 'ambulance') _fetchReturnRoute();
        }
      });
      return true;
    } catch (e) {
      debugPrint('[Response] Status update error: $e');
      _snack('Could not reach the server.');
      return false;
    }
  }

  Future<void> _completeResponse() async {
    if (_completing) return;
    setState(() => _completing = true);
    final ok = await _updateStatus('completed');
    if (!mounted) return;
    setState(() => _completing = false);
    // Only forget the resume state when the backend really closed the trip.
    if (ok) {
      Provider.of<TripsProvider>(context, listen: false).clearCurrentDispatch();
    }
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  // ── Map ───────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final center = _incident ?? _driver ?? const LatLng(20.5937, 78.9629);
    final hasRoute = _routePoints.length > 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppColors.radius),
      child: SizedBox(
        height: 320,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13,
                // Keep the driver centred until a route is available.
                onMapReady: _fitRoute,
                // A hand pan breaks follow mode; the recenter button restores it.
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture && _followDriver && mounted) {
                    setState(() => _followDriver = false);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.signalaid.app',
                ),
                if (hasRoute)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 5,
                        color: AppColors.primary,
                        borderStrokeWidth: 2,
                        borderColor: const Color(0xFF0B0D12),
                      ),
                      if (_returnPoints.length > 1)
                        Polyline(
                          points: _returnPoints,
                          strokeWidth: 4,
                          color: AppColors.success,
                          borderStrokeWidth: 2,
                          borderColor: const Color(0xFF0B0D12),
                        ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_incident != null)
                      Marker(
                        point: _incident!,
                        width: 46,
                        height: 46,
                        child: _pin('🚨', AppColors.primary),
                      ),
                    if (_driver != null)
                      Marker(
                        point: _driver!,
                        width: 46,
                        height: 46,
                        child: _pin('🚑', AppColors.success),
                      ),
                  ],
                ),
              ],
            ),

            // Recentre / follow + fit-route controls
            Positioned(
              right: 12,
              top: 12,
              child: Column(
                children: [
                  _mapButton(
                    icon: _followDriver ? Icons.navigation : Icons.my_location,
                    tooltip: _followDriver ? 'Following you' : 'Follow me',
                    highlighted: _followDriver,
                    onTap: () {
                      if (_driver != null) {
                        setState(() => _followDriver = true);
                        _mapController.move(_driver!, 15);
                      } else {
                        _snack('Waiting for your GPS position…');
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _mapButton(
                    icon: Icons.route,
                    tooltip: 'Fit the whole route',
                    onTap: () {
                      if (mounted) setState(() => _followDriver = false);
                      _fitRoute();
                    },
                  ),
                ],
              ),
            ),

            // Loading / error strip
            if (_loadingRoute || _routeError != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      if (_loadingRoute)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      else
                        const Icon(Icons.error_outline, size: 14, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Text(
                        _loadingRoute ? 'Calculating route…' : (_routeError ?? ''),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pin(String glyph, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: Center(child: Text(glyph, style: const TextStyle(fontSize: 18))),
    );
  }

  Widget _mapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlighted
            ? AppColors.success.withValues(alpha: 0.92)
            : AppColors.background.withValues(alpha: 0.92),
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(
              icon,
              size: 18,
              color: highlighted ? Colors.white : AppColors.foreground,
            ),
          ),
        ),
      ),
    );
  }

  // ── Small pieces ──────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
          color: AppColors.mutedForeground,
        ),
      );

  Widget _buildPulsingDot() => Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      );

  /// Emergency priority straight from the dispatch (incident type decides it).
  /// Never guessed locally.
  Widget _priorityChip() {
    final raw = (_dispatch?['priority'] ?? '').toString().toUpperCase();
    final label = raw.isEmpty ? null : raw;
    if (label == null) return const SizedBox.shrink();
    final color = label == 'CRITICAL'
        ? AppColors.critical
        : label == 'HIGH'
            ? AppColors.accent
            : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: color,
        ),
      ),
    );
  }

  /// EN_ROUTE → ARRIVED → RESOLVED, as confirmed by the backend.
  Widget _buildStatusStepper() {
    final steps = const ['EN_ROUTE', 'ARRIVED', 'RESOLVED'];
    int current;
    switch (_status) {
      case 'arrived':
        current = 1;
        break;
      case 'completed':
      case 'resolved':
        current = 2;
        break;
      default:
        current = 0;
    }

    return Row(
      children: List.generate(steps.length, (i) {
        final active = i <= current;
        final color = active ? AppColors.primary : AppColors.border;
        return Expanded(
          child: Column(
            children: [
              Container(
                height: 3,
                margin: EdgeInsets.only(right: i == steps.length - 1 ? 0 : 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                steps[i],
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: active ? AppColors.foreground : AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TripsProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 4),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                color: AppColors.primary,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 14,
                  left: 18,
                  right: 18,
                  bottom: 14,
                ),
                child: Row(
                  children: [
                    _buildPulsingDot(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Emergency vehicle en route',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Unit ${provider.driver?.vehicleNo ?? '—'} · ${provider.driver?.driverId ?? ''}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18, color: Colors.white),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Route map: driver → incident, on real roads ──
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: _buildMap(),
                      ),

                      const SizedBox(height: 16),

                      // ── Real route numbers from the routing provider ──
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _sectionLabel('ROUTE TO SCENE'),
                                Row(
                                  children: [
                                    _priorityChip(),
                                    if (_routeProvider != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Text(
                                          _routeProvider == 'osrm'
                                              ? 'Road route'
                                              : 'Straight line',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.mutedForeground,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Stat(
                                  label: 'Distance',
                                  value: _routeDistanceKm != null
                                      ? '${_routeDistanceKm!.toStringAsFixed(2)} km'
                                      : '—',
                                ),
                                Stat(
                                  label: 'ETA',
                                  value: _routeDurationMin != null ? '$_routeDurationMin min' : '—',
                                ),
                                Stat(
                                  label: 'GPS',
                                  value: _driver != null
                                      ? (_usingLastKnown ? 'Last known' : 'Active')
                                      : 'Searching',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildStatusStepper(),
                            const SizedBox(height: 14),

                            // Destination detail
                            Text(
                              '${_dispatch?['address'] ?? _dispatch?['description'] ?? 'Emergency location'}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.foreground,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _incident != null
                                  ? '🚨 Incident: ${_incident!.latitude.toStringAsFixed(5)}, ${_incident!.longitude.toStringAsFixed(5)}'
                                  : '🚨 Incident location unavailable',
                              style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                            ),
                            Text(
                              _driver != null
                                  ? '🚑 You: ${_driver!.latitude.toStringAsFixed(5)}, ${_driver!.longitude.toStringAsFixed(5)}${_usingLastKnown ? ' (last known)' : ''}'
                                  : _locationDenied
                                      ? '🚑 Location permission denied — enable it in Profile'
                                      : '🚑 Acquiring your GPS…',
                              style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                            ),
                            const SizedBox(height: 14),
                            PrimaryButton(
                              label: 'START NAVIGATION',
                              onPressed: _startNavigation,
                              variant: ButtonVariant.primary,
                              icon: Icons.navigation,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Ambulance return journey (fire vehicles skip this).
                      // Visible for the whole trip — drivers plan the way back
                      // before they even reach the scene. ──
                      if (provider.driver?.vehicleType == null ||
                          provider.driver?.vehicleType == 'ambulance')
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('WAY BACK — START POINT (HOSPITAL)'),
                              const SizedBox(height: 8),
                              Text(
                                _arrived
                                    ? 'Patient picked up — head back'
                                    : 'Return leg: scene → hospital',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Incident location ↓ Starting point (hospital)',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.mutedForeground,
                                    height: 1.6),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Stat(
                                    label: 'Return distance',
                                    value: _returnDistanceKm != null
                                        ? '${_returnDistanceKm!.toStringAsFixed(2)} km'
                                        : (_loadingReturn ? '…' : '—'),
                                  ),
                                  Stat(
                                    label: 'Return ETA',
                                    value: _returnDurationMin != null
                                        ? '${_returnDurationMin!} min'
                                        : (_loadingReturn ? '…' : '—'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              PrimaryButton(
                                label: 'NAVIGATE BACK',
                                onPressed: _navigateBack,
                                variant: ButtonVariant.success,
                                icon: Icons.alt_route,
                              ),
                            ],
                          ),
                        ),

                      if (provider.driver?.vehicleType == null ||
                          provider.driver?.vehicleType == 'ambulance')
                        const SizedBox(height: 16),

                      if (!_arrived)
                        PrimaryButton(
                          label: 'MARK ARRIVED',
                          onPressed: () => _updateStatus('arrived'),
                          variant: ButtonVariant.success,
                          icon: Icons.check_circle,
                        )
                      else
                        PrimaryButton(
                          label: _completing ? 'Completing…' : 'COMPLETE RESPONSE',
                          onPressed: _completeResponse,
                          disabled: _completing,
                          variant: ButtonVariant.primary,
                          icon: Icons.flag,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
