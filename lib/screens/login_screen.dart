import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/card.dart';
import '../widgets/motion.dart';
import '../widgets/primary_button.dart';

/// S1 — Driver Sign-In.
///
/// Prefills the stored Driver ID / vehicle number so a returning driver only
/// presses one button. Routing is not done here: the [SessionGate] moves the
/// app once the backend has confirmed the session.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _driverIdController = TextEditingController();
  final _vehicleNoController = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;

  static final _driverIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{2,19}$');
  static final _vehicleNoPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 -]{2,19}$');

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<TripsProvider>(context, listen: false);
    // Prefill from the last session so "login once" survives a sign-out or an
    // invalidated token without retyping.
    final stored = provider.driver;
    if (stored != null) {
      _driverIdController.text = stored.driverId;
      _vehicleNoController.text = stored.vehicleNo;
    }
    _notice = provider.consumeNotice();
  }

  String? _validateDriverId(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Driver ID is required';
    if (!_driverIdPattern.hasMatch(v)) {
      return '3-20 letters, numbers or dashes (e.g. DRV-204)';
    }
    return null;
  }

  String? _validateVehicleNo(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Vehicle number is required';
    if (!_vehicleNoPattern.hasMatch(v)) {
      return '3-20 letters, numbers, spaces or dashes (e.g. AMB-1187)';
    }
    return null;
  }

  Future<void> _handleLogin() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      setState(() {
        _error = null;
        _notice = null;
      });
      return;
    }

    final driverId = _driverIdController.text.trim();
    final vehicleNo = _vehicleNoController.text.trim();

    setState(() {
      _error = null;
      _notice = null;
      _busy = true;
    });

    final provider = Provider.of<TripsProvider>(context, listen: false);
    final err = await provider.loginDriver(driverId, vehicleNo);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    // On success, provider.session flips to pendingApproval/rejected/approved
    // and the SessionGate swaps this screen out.
  }

  @override
  Widget build(BuildContext context) {
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
              StaggerIn(
                child: Row(
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
                  ],
                ),
              ),
            const SizedBox(height: 28),

              // Form Card
              StaggerIn(
                delay: const Duration(milliseconds: 90),
                child: AppCard(
                child: Form(
                  key: _formKey,
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
                      _field(
                        controller: _driverIdController,
                        label: 'Driver ID',
                        hint: 'DRV-204',
                        validator: _validateDriverId,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _vehicleNoController,
                        label: 'Vehicle Number',
                        hint: 'AMB-1187',
                        validator: _validateVehicleNo,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _handleLogin(),
                      ),
                      if (_notice != null) ...[
                        const SizedBox(height: 14),
                        _banner(
                          text: _notice!,
                          icon: Icons.info_outline,
                          color: AppColors.accent,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _banner(
                          text: _error!,
                          icon: Icons.error_outline,
                          color: const Color(0xFFEF4444),
                        ),
                      ],
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: _busy ? 'Signing in…' : 'Active Response',
                        onPressed: _handleLogin,
                        disabled: _busy,
                        loading: _busy,
                        variant: ButtonVariant.primary,
                        icon: Icons.bolt,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pushNamed(context, '/register'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.foreground,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppColors.radius),
                            ),
                          ),
                          child: const Text('New Driver? Register for Approval'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ),

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
                      'Only admin-approved vehicles receive emergencies',
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      onChanged: (_) => setState(() {
        _error = null;
      }),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.mutedForeground),
        errorStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFFEF4444),
        ),
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
    );
  }

  Widget _banner({
    required String text,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.foreground.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
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
