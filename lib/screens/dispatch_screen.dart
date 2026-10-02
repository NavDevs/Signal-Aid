import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/card.dart';
import '../widgets/motion.dart';

/// Signal-Aid home: map first, verified job cards below.
///
/// The driver should answer in seconds: where am I, is there an emergency
/// nearby, what type is it, can I accept it, how do I get there. Everything
/// else was removed from this screen on purpose.
class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  bool _accepting = false;
  String? _acceptingId;
  LatLng? _myPosition;
  Timer? _refreshTimer;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshJobs(silent: true));
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _refreshJobs(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _refreshJobs({bool silent = false}) async {
    if (!mounted) return;
    final provider = Provider.of<TripsProvider>(context, listen: false);

    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          if (mounted) {
            setState(() => _myPosition = LatLng(position.latitude, position.longitude));
          }
        }
      }
    } catch (e) {
      debugPrint('[Duty] Location error: $e');
    }

    if (_myPosition != null) {
      await provider.fetchDispatches(lat: _myPosition!.latitude, lon: _myPosition!.longitude);
    } else {
      await provider.fetchDispatches();
    }
    // Keep the resume card in sync with server truth (trip completed/expired
    // elsewhere disappears, a trip started elsewhere appears).
    await provider.restoreActiveTrip();

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job list refreshed')),
      );
    }
  }

  Future<void> _acceptDispatch(
      BuildContext context, TripsProvider provider, Map<String, dynamic> dispatch) async {
    setState(() {
      _accepting = true;
      _acceptingId = dispatch['id']?.toString();
    });
    final trip = await provider.acceptDispatch(dispatch['id'].toString());
    if (!mounted) return;
    setState(() {
      _accepting = false;
      _acceptingId = null;
    });

    if (trip != null) {
      final tripId = (trip['id'] ?? dispatch['id']).toString();
      Navigator.pushNamed(context, '/response', arguments: {
        'tripId': tripId,
        'dispatch': dispatch,
        // Where this emergency journey starts (usually the hospital bay).
        // The response screen uses it for the ambulance way-back leg.
        if (_myPosition != null) 'startLat': _myPosition!.latitude,
        if (_myPosition != null) 'startLon': _myPosition!.longitude,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.lastAcceptError ?? 'REQUEST ALREADY TAKEN'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Honest pre-accept estimate from the backend-measured distance.
  /// The precise OSRM route appears after accepting.
  String _etaEstimate(Map<String, dynamic> dispatch) {
    final km = double.tryParse('${dispatch['distanceKm'] ?? ''}');
    if (km == null) return 'ETA —';
    final mins = (km / 30 * 60).ceil().clamp(1, 999);
    return '~$mins min';
  }

  /// Backend-authoritative countdown (resolution = reported + duration).
  String _remainingLabel(Map<String, dynamic> dispatch) {
    final secs = int.tryParse('${dispatch['remaining_seconds'] ?? ''}');
    if (secs == null) return 'time left —';
    if (secs <= 0) return 'expiring';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m left' : '${m}m left';
  }

  /// Android back on the duty dashboard = leaving the app. A driver who is
  /// still AVAILABLE would silently keep receiving dispatches while the app
  /// is closed, so they must switch OFFLINE first — the exit prompt makes
  /// that ask. BUSY cannot be changed mid-emergency (the response has to be
  /// finished first), and OFFLINE exits directly.
  Future<void> _confirmExit() async {
    final provider = context.read<TripsProvider>();
    final availability =
        (provider.driver?.availability ?? 'OFFLINE').toUpperCase();

    if (availability == 'OFFLINE') {
      SystemNavigator.pop();
      return;
    }

    if (!mounted) return;

    if (availability == 'BUSY') {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text(
            'Finish the emergency first',
            style: TextStyle(color: AppColors.foreground),
          ),
          content: const Text(
            'You are on an active response. Complete it with COMPLETE RESPONSE before leaving the app — availability cannot be turned off mid-emergency.',
            style: TextStyle(color: AppColors.mutedForeground),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK',
                  style: TextStyle(color: AppColors.foreground)),
            ),
          ],
        ),
      );
      return;
    }

    // AVAILABLE — the case that causes conflicts: ask to go offline first.
    final goOffline = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Turn off availability before exiting?',
          style: TextStyle(color: AppColors.foreground),
        ),
        content: const Text(
          'You are still marked AVAILABLE. New dispatches would keep coming to this device while the app is closed. Go OFFLINE so there are no conflicts?',
          style: TextStyle(color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay',
                style: TextStyle(color: AppColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Go offline & exit',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (goOffline != true || !mounted) return;

    final error = await provider.setAvailability('OFFLINE');
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Could not go offline: $error — you are still in the app.')),
      );
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TripsProvider>(context);
    final resume = _resumeTrip(provider);

    final incidentPoints = <LatLng>[];
    for (final d in provider.incomingIncidents) {
      final lat = double.tryParse('${d['latitude'] ?? ''}');
      final lon = double.tryParse('${d['longitude'] ?? ''}');
      if (lat != null && lon != null) incidentPoints.add(LatLng(lat, lon));
    }

    final availability = (provider.driver?.availability ?? 'OFFLINE').toUpperCase();
    final availColor = availability == 'AVAILABLE'
        ? AppColors.success
        : availability == 'BUSY'
            ? AppColors.accent
            : AppColors.mutedForeground;
    final driverSub = [
      if ((provider.driver?.vehicleNo ?? '').isNotEmpty) provider.driver!.vehicleNo,
      if ((provider.driver?.organization ?? '').isNotEmpty) provider.driver!.organization,
    ].join('  ·  ');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Compact header: identity + quick actions on row one,
            //    duty switch alone on row two — the two can never collide,
            //    on any screen width. ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.emergency, size: 20, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.driver?.displayName ?? 'Emergency Response',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.foreground,
                              ),
                            ),
                            if (driverSub.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                driverSub,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _refreshJobs(),
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: 'Refresh jobs',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.card,
                          foregroundColor: AppColors.foreground,
                          side: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: () => Navigator.pushNamed(context, '/history'),
                        icon: const Icon(Icons.access_time, size: 18),
                        tooltip: 'Response history',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.card,
                          foregroundColor: AppColors.foreground,
                          side: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: () => Navigator.pushNamed(context, '/profile'),
                        icon: const Icon(Icons.person_outline, size: 18),
                        tooltip: 'Profile & logout',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.card,
                          foregroundColor: AppColors.foreground,
                          side: const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Duty switch: full-width, own row. The label shrinks with
                  // an ellipsis instead of running under the buttons.
                  GestureDetector(
                    onTap: () {
                      if (availability == 'BUSY') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'You are on an active emergency — finish it with COMPLETE RESPONSE first.'),
                          ),
                        );
                        return;
                      }
                      final next = availability == 'AVAILABLE'
                          ? 'OFFLINE'
                          : 'AVAILABLE';
                      provider.setAvailability(next);
                    },
                    child: Opacity(
                      opacity: availability == 'BUSY' ? 0.75 : 1.0,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: availColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: availColor.withValues(alpha: 0.55),
                              width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                  color: availColor,
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                availability == 'BUSY'
                                    ? 'BUSY · on emergency'
                                    : availability == 'AVAILABLE'
                                        ? 'AVAILABLE · tap to go OFFLINE'
                                        : 'OFFLINE · tap to go AVAILABLE',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                  color: availColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              availability == 'AVAILABLE'
                                  ? Icons.toggle_on
                                  : Icons.toggle_off,
                              size: 20,
                              color: availColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (provider.offline)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppColors.radius),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_off, size: 14, color: AppColors.accent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline — new emergencies may not arrive until the server is reachable.',
                        style: TextStyle(fontSize: 11, color: AppColors.foreground),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Everything below the banner scrolls as one piece — resume
            //    card, compact map and the job list can never overlap or
            //    overflow, however short the screen is. ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (resume != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: StaggerIn(
                          child: _buildResumeCard(context, resume),
                        ),
                      ),

                    // ── Compact map: a glance, not the whole screen ──
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, resume != null ? 12 : 8, 16, 0),
                      child: SizedBox(
                        height: (MediaQuery.sizeOf(context).height * 0.26)
                            .clamp(160.0, 260.0)
                            .toDouble(),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          child: Stack(
                    children: [
                      if (_myPosition == null && incidentPoints.isEmpty)
                        Container(
                          color: AppColors.card,
                          alignment: Alignment.center,
                          child: const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Waiting for your GPS position and the first verified incident…',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                            ),
                          ),
                        )
                      else
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _myPosition ??
                                (incidentPoints.isNotEmpty
                                    ? incidentPoints.first
                                    : const LatLng(12.9716, 77.5946)),
                            initialZoom: 12,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.signalaid.app',
                            ),
                            MarkerLayer(
                              markers: [
                                ...incidentPoints.map((point) => Marker(
                                      point: point,
                                      width: 40,
                                      height: 40,
                                      child: _buildMapPin(
                                          Icons.warning_rounded, Colors.red),
                                    )),
                                if (_myPosition != null)
                                  Marker(
                                    point: _myPosition!,
                                    width: 44,
                                    height: 44,
                                    child: _buildMapPin(
                                        Icons.navigation, AppColors.success),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B0D12).withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${provider.incomingIncidents.length} verified incident(s)',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      if (_myPosition != null)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: FloatingActionButton.small(
                            heroTag: 'recenter',
                            backgroundColor: AppColors.card,
                            foregroundColor: AppColors.foreground,
                            onPressed: () => _mapController.move(_myPosition!, 14),
                            child: const Icon(Icons.my_location, size: 18),
                          ),
                        ),
                    ],
                  ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Emergency request cards (animated in/out as jobs arrive or lock) ──
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeOutQuad,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: provider.incomingIncidents.isEmpty
                          ? const Center(
                              key: ValueKey('empty'),
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_outline,
                                        size: 34, color: AppColors.success),
                                    SizedBox(height: 10),
                                    Text(
                                      'All clear — no verified emergencies for your vehicle.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.foreground,
                                          height: 1.6),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'New requests appear here instantly.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 12, color: AppColors.mutedForeground),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              key: ValueKey(provider.incomingIncidents
                                  .map((d) => d['id'])
                                  .join(',')),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0;
                                    i < provider.incomingIncidents.length;
                                    i++)
                                  StaggerIn.index(
                                    index: i,
                                    stepMs: 40,
                                    maxDelayMs: 240,
                                    child: _buildRequestCard(context, provider,
                                        provider.incomingIncidents[i]),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// The in-progress trip, if the backend still reports it as open.
  Map<String, dynamic>? _resumeTrip(TripsProvider provider) {
    final trip = provider.activeTrip;
    if (trip == null || trip['id'] == null) return null;
    final status = (trip['status'] ?? '').toString().toLowerCase();
    if (status != 'en_route' && status != 'arrived') return null;
    return trip;
  }

  Widget _buildResumeCard(BuildContext context, Map<String, dynamic> trip) {
    final rawType = (trip['type'] ?? 'emergency').toString().toLowerCase();
    final isFire = rawType == 'fire';
    final address = (trip['address'] ?? trip['description'] ?? 'Incident location').toString();
    final status = (trip['status'] ?? '').toString();
    final arrived = status.toLowerCase() == 'arrived';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emergency, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACTIVE RESPONSE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${isFire ? 'Fire' : 'Emergency'} · ${arrived ? 'Arrived at scene' : 'En route'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mutedForeground,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/response', arguments: {
                'tripId': trip['id'].toString(),
                'dispatch': trip,
                'status': status.isEmpty ? 'en_route' : status,
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppColors.radius),
                ),
              ),
              child: const Text('RESUME RESPONSE',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(
      BuildContext context, TripsProvider provider, Map<String, dynamic> dispatch) {
    final rawType = (dispatch['type'] ?? 'emergency').toString().toLowerCase();
    final isFire = rawType == 'fire';
    final title = isFire ? '🔥 FIRE' : '🚨 ACCIDENT';
    final address = (dispatch['address'] ?? 'Unknown location').toString();
    final description = (dispatch['description'] ?? '').toString();
    final photoUrl = (dispatch['photo_url'] ?? '').toString();
    final priority = (dispatch['priority'] ?? '').toString();
    final km = double.tryParse('${dispatch['distanceKm'] ?? ''}');
    final distLabel = km != null ? '${km.toStringAsFixed(1)} km' : 'distance —';
    final busy = _accepting && _acceptingId == dispatch['id']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: AppColors.foreground,
                    ),
                  ),
                ),
                if (priority.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      priority,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
            // The actual incident photo from the citizen's report.
            if (photoUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppColors.radius),
                      child: Image.network(
                        photoUrl,
                        fit: BoxFit.contain,
                        // Cap decode size so a huge upload can't blow up
                        // memory when the fullscreen dialog opens.
                        cacheWidth: 1920,
                        frameBuilder: (context, child, frame, wasSync) {
                          if (wasSync) return child;
                          return AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            child: child,
                          );
                        },
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppColors.radius),
                  child: Image.network(
                    photoUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    // Decode near display size so big uploads don't spike
                    // memory while the job card is on screen.
                    cacheWidth: 800,
                    frameBuilder: (context, child, frame, wasSync) {
                      if (wasSync) return child;
                      return AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        child: child,
                      );
                    },
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '$distLabel • ${_etaEstimate(dispatch)} • ${_remainingLabel(dispatch)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Location:\n$address',
              style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground, height: 1.5),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Description:\n$description',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.foreground, height: 1.5),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _accepting ? null : () => _acceptDispatch(context, provider, dispatch),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppColors.radius),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('ACCEPT EMERGENCY',
                        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPin(IconData icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }
}
