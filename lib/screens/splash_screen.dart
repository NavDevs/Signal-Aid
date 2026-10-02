import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// S0 — Splash / Session Restore.
///
/// Shown only while the backend is being asked whether the stored token is
/// still good. The driver never types credentials here: that is the whole
/// point of "login once" (spec §7).
///
/// Deliberately provider-free so the boot gate stays the only thing that
/// knows about session state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.offline = false});

  /// True when the app already knows it will start without the server.
  final bool offline;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    lowerBound: 0.96,
    upperBound: 1.04,
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (!reduce && !_pulse.isAnimating) _pulse.repeat(reverse: true);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: reduce ? const AlwaysStoppedAnimation(1) : _pulse,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppColors.radius),
                  ),
                  child: const Icon(Icons.add, size: 36, color: Colors.white),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'SignalAid',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Emergency Response System',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
              const SizedBox(height: 14),
              Text(
                widget.offline ? 'Starting offline…' : 'Verifying your session…',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
