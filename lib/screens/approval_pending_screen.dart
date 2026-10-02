import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/card.dart';
import '../widgets/primary_button.dart';

/// S3 — Approval Pending / Rejected.
///
/// The app never grants itself access: this screen only reflects what the
/// backend said. When an admin approves, the `driver_approval_updated` socket
/// event makes the provider re-check, and the [SessionGate] moves the driver on
/// without them touching anything.
class ApprovalPendingScreen extends StatefulWidget {
  const ApprovalPendingScreen({super.key});

  @override
  State<ApprovalPendingScreen> createState() => _ApprovalPendingScreenState();
}

class _ApprovalPendingScreenState extends State<ApprovalPendingScreen> {
  bool _checking = false;

  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    final provider = Provider.of<TripsProvider>(context, listen: false);
    await provider.refreshProfile();
    if (!mounted) return;
    setState(() => _checking = false);

    if (provider.approved) {
      // The SessionGate swaps this screen out for the duty dashboard.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Approved! Loading your duty dashboard…'),
          backgroundColor: AppColors.success,
        ),
      );
    } else if (!provider.awaitingApproval && !provider.rejected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reach the server. Try again.')),
      );
    }
  }

  Future<void> _logout() async {
    await Provider.of<TripsProvider>(context, listen: false).logout();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripsProvider>();
    final isRejected = provider.rejected;
    final driver = provider.driver;
    final accent = isRejected ? AppColors.destructive : AppColors.accent;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 40),
              AppCard(
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        isRejected ? Icons.gpp_bad : Icons.hourglass_top,
                        color: accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      isRejected ? 'Registration Rejected' : 'Waiting for Admin Approval',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isRejected
                          ? 'An administrator rejected this registration, so emergency dispatch stays locked.'
                          : 'Your registration is with the dispatch control room. You can sign in and receive emergencies as soon as an admin approves it.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.mutedForeground,
                        height: 1.5,
                      ),
                    ),
                    if (driver != null) ...[
                      const SizedBox(height: 18),
                      _summaryRow('Driver', driver.displayName),
                      _summaryRow('Driver ID', driver.driverId),
                      _summaryRow('Vehicle', driver.vehicleNo),
                      if ((driver.vehicleType ?? '').isNotEmpty)
                        _summaryRow('Type', driver.vehicleType!),
                      if ((driver.organization ?? '').isNotEmpty)
                        _summaryRow('Organization', driver.organization!),
                    ],
                    if (isRejected && (provider.rejectionReason ?? '').isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.destructive.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          border: Border.all(
                            color: AppColors.destructive.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'REASON FROM ADMIN',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: AppColors.destructive,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              provider.rejectionReason!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.foreground,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: _checking ? 'Checking…' : 'Check Again',
                      onPressed: _checkAgain,
                      disabled: _checking,
                      loading: _checking,
                      variant: ButtonVariant.primary,
                      icon: Icons.refresh,
                    ),
                    if (isRejected) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pushNamed(context, '/register'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.foreground,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppColors.radius),
                            ),
                          ),
                          child: const Text('Submit a new registration'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _logout,
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Approval can only be granted by an administrator. The Signal Aid app cannot approve itself.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.mutedForeground,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
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
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
