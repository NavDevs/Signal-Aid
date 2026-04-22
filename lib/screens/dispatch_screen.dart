import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/trip.dart';
import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../utils/dispatch_helper.dart';
import '../widgets/card.dart';
import '../widgets/criticality_picker.dart';
import '../widgets/primary_button.dart';
import '../widgets/stat.dart';

class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  Criticality _criticality = Criticality.high;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TripsProvider>(context);
    final plan = DispatchHelper.computeDispatchPlan(_criticality);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // Header
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.chevron_left, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: AppColors.foreground,
                      side: BorderSide(color: AppColors.border),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pre-flight',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                        const Text(
                          'Plan Response',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: AppColors.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Driver Info
              if (provider.driver != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildDriverChip(Icons.person, provider.driver!.driverId),
                    const SizedBox(width: 8),
                    _buildDriverChip(Icons.local_shipping, provider.driver!.vehicleNo),
                  ],
                ),
              ],
              
              const SizedBox(height: 16),
              
              // Map Card
              AppCard(
                padding: EdgeInsets.zero,
                child: SizedBox(
                  height: 240,
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1C2233), Color(0xFF0F1320)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(AppColors.radius)),
                        ),
                      ),
                      // Grid lines
                      ...List.generate(6, (i) => Positioned(
                        top: ((i + 1) * 14).toDouble(),
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 0.5,
                          color: AppColors.border.withValues(alpha: 0.5),
                        ),
                      )),
                      ...List.generate(5, (i) => Positioned(
                        left: ((i + 1) * 16).toDouble(),
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 0.5,
                          color: AppColors.border.withValues(alpha: 0.5),
                        ),
                      )),
                      // Route line
                      Positioned(
                        left: '16%'.contains('%') ? 0 : 16,
                        right: 14,
                        top: 22,
                        bottom: 30,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: const Color(0xFFEF2B2B), width: 3),
                              top: BorderSide(color: const Color(0xFFEF2B2B), width: 3),
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                            ),
                          ),
                        ),
                      ),
                      // Pins
                      Positioned(
                        left: '12%'.contains('%') ? 0 : 12,
                        top: '70%'.contains('%') ? 0 : 70,
                        child: _buildMapPin(Icons.navigation, AppColors.primary),
                      ),
                      Positioned(
                        right: 10,
                        top: 18,
                        child: _buildMapPin(Icons.add, AppColors.success, iconColor: const Color(0xFF03110A)),
                      ),
                      // Badge
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B0D12).withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
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
                                'Live route',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.6,
                                  color: Colors.white,
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
              
              const SizedBox(height: 16),
              
              // ETA Card
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estimated Arrival',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${plan.eta}',
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -2,
                            color: AppColors.foreground,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'seconds',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Stat(label: 'Distance', value: '${plan.distance.toStringAsFixed(1)} km'),
                        Stat(label: 'Avg speed', value: '${plan.speed} km/h'),
                        Stat(
                          label: 'Preempts',
                          value: '${plan.preemptions.length}',
                          color: AppColors.accent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 18),
              
              // Criticality Picker
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Severity',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 10),
                  CriticalityPicker(
                    value: _criticality,
                    onChange: (value) => setState(() => _criticality = value),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _criticality == Criticality.critical
                        ? 'Maximum signal preemption. All upstream lights cleared.'
                        : _criticality == Criticality.high
                            ? 'Aggressive preemption on high-traffic corridors.'
                            : 'Standard escort. Preempt only at signalised junctions.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.mutedForeground,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              PrimaryButton(
                label: 'Start Response',
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/response',
                    arguments: {'criticality': _criticality.name},
                  );
                },
                variant: ButtonVariant.success,
                icon: Icons.play_arrow,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.mutedForeground),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPin(IconData icon, Color color, {Color? iconColor}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: 14, color: iconColor ?? Colors.white),
    );
  }
}
