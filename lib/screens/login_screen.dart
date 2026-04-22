import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/driver.dart';
import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/card.dart';
import '../widgets/primary_button.dart';
import '../widgets/stat.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _driverIdController = TextEditingController();
  final _vehicleNoController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<TripsProvider>(context, listen: false);
    if (provider.driver != null) {
      _driverIdController.text = provider.driver!.driverId;
      _vehicleNoController.text = provider.driver!.vehicleNo;
    }
  }

  void _handleLogin() async {
    if (_driverIdController.text.trim().isEmpty || _vehicleNoController.text.trim().isEmpty) {
      setState(() => _error = 'Driver ID and vehicle number are required.');
      return;
    }
    
    setState(() => _error = null);
    
    final provider = Provider.of<TripsProvider>(context, listen: false);
    await provider.setDriver(Driver(
      driverId: _driverIdController.text.trim(),
      vehicleNo: _vehicleNoController.text.trim(),
    ));
    
    if (mounted) {
      Navigator.pushNamed(context, '/dispatch');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TripsProvider>(context);
    final last = provider.trips.isNotEmpty ? provider.trips.first : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              // Brand Row
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppColors.radius),
                    ),
                    child: const Icon(Icons.add, size: 26, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SignalAid',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: AppColors.foreground,
                        ),
                      ),
                      Text(
                        'Emergency Response System',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pushNamed(context, '/history'),
                    icon: const Icon(Icons.access_time, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: AppColors.foreground,
                      side: BorderSide(color: AppColors.border),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              
              // Form Card
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Driver Sign-In',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _driverIdController,
                      onChanged: (_) => setState(() => _error = null),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Driver ID',
                        hintText: 'DRV-204',
                        hintStyle: const TextStyle(color: AppColors.mutedForeground),
                        filled: true,
                        fillColor: AppColors.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _vehicleNoController,
                      onChanged: (_) => setState(() => _error = null),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Vehicle Number',
                        hintText: 'AMB-1187',
                        hintStyle: const TextStyle(color: AppColors.mutedForeground),
                        filled: true,
                        fillColor: AppColors.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: Color(0xFFFCA5A5)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFFECACA),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    PrimaryButton(
                      label: 'Active Response',
                      onPressed: _handleLogin,
                      variant: ButtonVariant.danger,
                      icon: Icons.bolt,
                    ),
                  ],
                ),
              ),
              
              // Last Trip Card
              if (last != null) ...[
                const SizedBox(height: 18),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Last Run',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                          Text(
                            '${last.date} · ${last.time}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Stat(
                            label: 'Travel',
                            value: '${last.travelTime.toStringAsFixed(1)}s',
                            color: AppColors.success,
                          ),
                          Stat(
                            label: 'Preempts',
                            value: '${last.preemptions}',
                            color: AppColors.accent,
                          ),
                          Stat(
                            label: 'ML Conf.',
                            value: '${last.confidence}%',
                            color: const Color(0xFF60A5FA),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/history'),
                        child: Row(
                          children: [
                            Text(
                              'View trip history',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward, size: 14, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'ML preemption network online',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _driverIdController.dispose();
    _vehicleNoController.dispose();
    super.dispose();
  }
}
