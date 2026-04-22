import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/intersection.dart';
import '../models/trip.dart';
import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../utils/dispatch_helper.dart';
import '../widgets/card.dart';
import '../widgets/primary_button.dart';
import '../widgets/stat.dart';

class ResponseScreen extends StatefulWidget {
  const ResponseScreen({super.key});

  @override
  State<ResponseScreen> createState() => _ResponseScreenState();
}

class _ResponseScreenState extends State<ResponseScreen> with SingleTickerProviderStateMixin {
  late DispatchPlan _plan;
  late Criticality _criticality;
  int _eta = 0;
  int _speed = 0;
  List<Intersection> _intersections = [];
  bool _arriving = false;
  Timer? _timer;
  DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeData();
    _startTimer();
  }

  void _initializeData() {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _criticality = Criticality.values.firstWhere(
      (e) => e.name == args?['criticality'],
      orElse: () => Criticality.high,
    );
    _plan = DispatchHelper.computeDispatchPlan(_criticality);
    _eta = _plan.eta;
    _speed = _plan.speed;
    _intersections = _plan.preemptions.map((i) => Intersection(
      id: i.id,
      name: i.name,
      distanceKm: i.distanceKm,
      status: IntersectionStatus.preempted,
    )).toList();
    _startTime = DateTime.now();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _eta = (_eta - 1).clamp(0, _plan.eta);
        if (_eta == 0) _arriving = true;
        
        final drift = ((DateTime.now().millisecond % 8) - 4);
        _speed = (_speed + drift).clamp(30, 72);
        
        final total = _plan.eta;
        final elapsed = total - _eta;
        _intersections = _intersections.asMap().entries.map((entry) {
          final idx = entry.key;
          final it = entry.value;
          final triggerAt = ((idx + 1) / (_intersections.length + 1)) * total;
          
          if (elapsed > triggerAt + 8) {
            return Intersection(id: it.id, name: it.name, distanceKm: it.distanceKm, status: IntersectionStatus.passed);
          } else if (elapsed > triggerAt) {
            return Intersection(id: it.id, name: it.name, distanceKm: it.distanceKm, status: IntersectionStatus.preempted);
          }
          return it;
        }).toList();
      });
    });
  }

  Future<void> _handleArrived() async {
    final provider = Provider.of<TripsProvider>(context, listen: false);
    final driver = provider.driver;
    
    final elapsedSec = DateTime.now().difference(_startTime).inSeconds.toDouble();
    final travelTime = math.max(elapsedSec, _plan.eta - _eta.toDouble());
    
    await provider.addTrip(
      travelTime: travelTime,
      preemptions: _plan.preemptions.length,
      confidence: _plan.confidence,
      distance: _plan.distance,
      criticality: _criticality,
      driverId: driver?.driverId ?? '—',
      vehicleNo: driver?.vehicleNo ?? '—',
    );
    
    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TripsProvider>(context);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Alert frame
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 4),
              ),
            ),
          ),
          
          Column(
            children: [
              // Banner
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
                    const Expanded(
                      child: Text(
                        'Emergency vehicle en route',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: Colors.white,
                        ),
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
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      
                      // Hero Card
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF2A0A0A), Color(0xFF0B0D12)],
                            ),
                            borderRadius: BorderRadius.all(Radius.circular(AppColors.radius)),
                          ),
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Time to scene',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.4,
                                  color: Color(0xFFA5A5A5),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_eta}s',
                                style: const TextStyle(
                                  fontSize: 72,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -3,
                                  height: 0.9,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Stat(label: 'Speed', value: '$_speed km/h', color: Colors.white),
                                  Stat(label: 'Distance', value: '${_plan.distance.toStringAsFixed(1)} km', color: Colors.white),
                                  Stat(label: 'Conf.', value: '${_plan.confidence}%', color: Colors.white),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Intersections Card
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Upcoming Intersections',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.4,
                                    color: AppColors.mutedForeground,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: AppColors.success,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Cleared',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Column(
                              children: _intersections.map((it) => _buildIntersectionRow(it)).toList(),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Driver Card
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Driver',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.4,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        provider.driver?.driverId ?? 'Unknown',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.foreground,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Unit ${provider.driver?.vehicleNo ?? '—'}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.mutedForeground,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildCriticalityBadge(),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      PrimaryButton(
                        label: _arriving ? 'Arrived — Mark Complete' : 'Mark Arrived',
                        onPressed: _handleArrived,
                        variant: ButtonVariant.success,
                        icon: Icons.check_circle,
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

  Widget _buildPulsingDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 700),
      builder: (context, value, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildIntersectionRow(Intersection item) {
    final statusMap = {
      IntersectionStatus.preempted: {
        'label': 'Preempted',
        'bg': const Color(0xFF22C55E).withValues(alpha: 0.12),
        'border': const Color(0xFF22C55E).withValues(alpha: 0.4),
        'color': AppColors.success,
        'icon': Icons.check,
      },
      IntersectionStatus.passed: {
        'label': 'Cleared',
        'bg': const Color(0xFF60A5FA).withValues(alpha: 0.10),
        'border': const Color(0xFF60A5FA).withValues(alpha: 0.35),
        'color': const Color(0xFF60A5FA),
        'icon': Icons.check_circle,
      },
      IntersectionStatus.queued: {
        'label': 'Queued',
        'bg': const Color(0xFFF59E0B).withValues(alpha: 0.12),
        'border': const Color(0xFFF59E0B).withValues(alpha: 0.4),
        'color': AppColors.accent,
        'icon': Icons.access_time,
      },
    }[item.status]!;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: statusMap['bg'] as Color,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: statusMap['border'] as Color),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: statusMap['color'] as Color,
                  borderRadius: BorderRadius.circular(AppColors.radius),
                ),
                child: Icon(statusMap['icon'] as IconData, size: 14, color: const Color(0xFF0B0D12)),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.id} · ${item.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Text(
            statusMap['label'] as String,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: statusMap['color'] as Color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCriticalityBadge() {
    final color = _criticality == Criticality.critical
        ? AppColors.critical
        : _criticality == Criticality.high
            ? AppColors.accent
            : AppColors.success;
    
    final bgColor = _criticality == Criticality.critical
        ? const Color(0xFFEF2B2B).withValues(alpha: 0.18)
        : _criticality == Criticality.high
            ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
            : const Color(0xFF22C55E).withValues(alpha: 0.18);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        _criticality.name.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: color,
        ),
      ),
    );
  }
}
