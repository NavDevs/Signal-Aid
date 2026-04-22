import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

enum ButtonVariant { primary, danger, ghost, success }

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final ButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool disabled;
  final bool fullWidth;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.disabled = false,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = {
      ButtonVariant.primary: {'bg': AppColors.primary, 'fg': AppColors.primaryForeground},
      ButtonVariant.danger: {'bg': const Color(0xFFDC2626), 'fg': Colors.white},
      ButtonVariant.ghost: {'bg': AppColors.secondary, 'fg': AppColors.foreground},
      ButtonVariant.success: {'bg': AppColors.success, 'fg': const Color(0xFF03110A)},
    }[variant]!;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: disabled || loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette['bg'],
          foregroundColor: palette['fg'],
          disabledBackgroundColor: palette['bg']?.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radius),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
