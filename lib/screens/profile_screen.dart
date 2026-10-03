import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/card.dart';
import '../widgets/primary_button.dart';

/// S9 — Profile & Settings.
///
/// The only place a session ends deliberately (spec §7), plus the driver's own
/// view of what the admin approved. Corrective changes route through the admin —
/// a driver can never edit an approved field.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  String _locationText = 'Checking…';
  bool _locationBlocked = false;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLocationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The driver may have changed permission in the OS settings screen.
    if (state == AppLifecycleState.resumed) _refreshLocationStatus();
  }

  Future<void> _refreshLocationStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;
      setState(() {
        _locationBlocked = permission == LocationPermission.deniedForever;
        if (!serviceEnabled) {
          _locationText = 'Location services are off';
        } else {
          switch (permission) {
            case LocationPermission.always:
              _locationText = 'Always allowed · required for dispatch';
            case LocationPermission.whileInUse:
              _locationText = 'Allowed while using the app';
            case LocationPermission.deniedForever:
              _locationText = 'Blocked in system settings';
            default:
              _locationText = 'Not granted';
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _locationText = 'Unavailable');
    }
  }

  Future<void> _handleLocationTap() async {
    if (_locationBlocked) {
      await Geolocator.openAppSettings();
      return;
    }
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }
    await _refreshLocationStatus();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Log out?', style: TextStyle(color: AppColors.foreground)),
        content: const Text(
          'You will stop receiving emergency requests on this device.',
          style: TextStyle(color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out', style: TextStyle(color: AppColors.destructive)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);
    await Provider.of<TripsProvider>(context, listen: false).logout();
    if (!mounted) return;
    // The session change swaps the gate's home screen to the sign-in screen,
    // but /profile was pushed ON TOP of it — pop everything back to the root
    // so the driver actually lands on the fresh login page instead of this
    // screen's "Logging out…" spinner.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripsProvider>();
    final driver = provider.driver;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile & Settings', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left, size: 20),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Identity
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppColors.radius),
                          ),
                          child: const Icon(Icons.person, color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driver?.displayName ?? 'Unknown driver',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.foreground,
                                ),
                              ),
                              Text(
                                driver?.driverId ?? '—',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _statusBadge(provider),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _row('Phone', driver?.phone),
                    _row('Vehicle number', driver?.vehicleNo),
                    _row('Vehicle type', driver?.vehicleType),
                    _row('Organization', driver?.organization),
                    
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Permissions
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PERMISSIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _locationText == 'Not granted' || _locationBlocked
                            ? Icons.location_disabled
                            : Icons.my_location,
                        color: _locationText == 'Not granted' || _locationBlocked
                            ? AppColors.destructive
                            : AppColors.success,
                        size: 20,
                      ),
                      title: const Text(
                        'Location',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.foreground,
                        ),
                      ),
                      subtitle: Text(
                        _locationText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: _handleLocationTap,
                        child: Text(_locationBlocked ? 'Settings' : 'Grant'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Session
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SESSION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      provider.offline
                          ? 'Started offline. Sign in again once you have a connection so the server can re-check your approval.'
                          : 'Approved by the backend. Your session restores automatically when you reopen the app.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedForeground,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'You are signed out only when you choose it, or when the server invalidates your session.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedForeground,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              PrimaryButton(
                label: _loggingOut ? 'Logging out…' : 'Log out',
                onPressed: _confirmLogout,
                disabled: _loggingOut,
                loading: _loggingOut,
                variant: ButtonVariant.ghost,
                icon: Icons.logout,
              ),

              const SizedBox(height: 14),
              const Center(
                child: Text(
                  'Need to change your vehicle, organization or licence?\nContact your dispatch administrator.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.mutedForeground,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(TripsProvider provider) {
    final status = provider.approvalStatus ??
        (provider.approved ? 'approved' : provider.awaitingApproval ? 'pending' : 'unknown');
    final color = status == 'approved'
        ? AppColors.success
        : status == 'rejected'
            ? AppColors.destructive
            : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: color,
        ),
      ),
    );
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              (value == null || value.isEmpty) ? '—' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
