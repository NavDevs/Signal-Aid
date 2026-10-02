import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/card.dart';
import '../widgets/primary_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _driverId = TextEditingController();
  final _vehicleNo = TextEditingController();
  final _org = TextEditingController();
  String _vehicleType = 'ambulance';
  String? _error;
  String? _success;
  bool _busy = false;

  static final _driverIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{2,19}$');
  static final _vehicleNoPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 -]{2,19}$');
  static final _digitsOnly = RegExp(r'\D');

  String? _validateName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Full name is required';
    if (v.length < 2) return 'Name must be at least 2 characters';
    if (v.length > 80) return 'Name must be 80 characters or fewer';
    return null;
  }

  String? _validatePhone(String? value) {
    final v = (value ?? '').replaceAll(_digitsOnly, '');
    if (v.isEmpty) return 'Phone number is required';
    if (v.length != 10) return 'Enter a valid 10-digit phone number';
    return null;
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

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      setState(() {
        _error = null;
        _success = null;
      });
      return;
    }

    setState(() {
      _error = null;
      _success = null;
      _busy = true;
    });
    final provider = Provider.of<TripsProvider>(context, listen: false);
    final err = await provider.registerDriver(
      name: _name.text.trim(),
      phone: _phone.text.replaceAll(_digitsOnly, ''),
      driverId: _driverId.text.trim().toUpperCase(),
      vehicleNo: _vehicleNo.text.trim().toUpperCase(),
      vehicleType: _vehicleType,
      organization: _org.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
    });
    if (err == null) {
      setState(() {
        _success = 'Registration submitted. Wait for admin approval, then login.';
      });
    } else {
      setState(() {
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Driver Registration')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AppCard(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('NEW DRIVER → ADMIN APPROVAL → LOGIN',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.mutedForeground)),
                  const SizedBox(height: 14),
                  _field(_name, 'Full Name', 'Naveen', validator: _validateName, textInputAction: TextInputAction.next),
                  const SizedBox(height: 12),
                  _field(_phone, 'Phone Number', '9876543210', keyboard: TextInputType.phone, validator: _validatePhone, maxLength: 14, textInputAction: TextInputAction.next),
                  const SizedBox(height: 12),
                  _field(_driverId, 'Driver ID', 'DRV-204', validator: _validateDriverId, textInputAction: TextInputAction.next),
                  const SizedBox(height: 12),
                  _field(_vehicleNo, 'Vehicle Number', 'AMB-1187', validator: _validateVehicleNo, textInputAction: TextInputAction.next),
                  const SizedBox(height: 12),
                  const Text('Vehicle Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.foreground)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _typeChip('ambulance', Icons.local_hospital, 'Ambulance'),
                      const SizedBox(width: 10),
                      _typeChip('fire', Icons.local_fire_department, 'Fire'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _field(_org, 'Organization / Hospital / Fire Station', 'City Hospital', textInputAction: TextInputAction.done),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                  if (_success != null) ...[
                    const SizedBox(height: 12),
                    Text(_success!, style: const TextStyle(color: AppColors.success, fontSize: 13)),
                  ],
                  const SizedBox(height: 16),
                  PrimaryButton(label: _busy ? 'Submitting…' : 'Submit for Approval', onPressed: _submit, disabled: _busy, loading: _busy, variant: ButtonVariant.primary, icon: Icons.send),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint, {
    TextInputType? keyboard,
    String? Function(String?)? validator,
    TextInputAction textInputAction = TextInputAction.next,
    int? maxLength,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: keyboard,
      validator: validator,
      textInputAction: textInputAction,
      maxLength: maxLength,
      onChanged: (_) => setState(() {
        _error = null;
      }),
      style: const TextStyle(color: AppColors.foreground, fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.mutedForeground),
        errorStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFFEF4444)),
        filled: true,
        fillColor: AppColors.secondary,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radius), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radius), borderSide: const BorderSide(color: AppColors.border)),
      ),
    );
  }

  Widget _typeChip(String value, IconData icon, String label) {
    final active = _vehicleType == value;
    return GestureDetector(
      onTap: () => setState(() => _vehicleType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? AppColors.primary : AppColors.border),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: active ? Colors.white : AppColors.foreground),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: active ? Colors.white : AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
    );
  }
}
