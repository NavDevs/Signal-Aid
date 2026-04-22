import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../utils/app_colors.dart';

class CriticalityPicker extends StatelessWidget {
  final Criticality value;
  final Function(Criticality) onChange;

  const CriticalityPicker({
    super.key,
    required this.value,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      {'value': Criticality.normal, 'label': 'Normal', 'color': const Color(0xFF22C55E)},
      {'value': Criticality.high, 'label': 'High', 'color': const Color(0xFFF59E0B)},
      {'value': Criticality.critical, 'label': 'Critical', 'color': const Color(0xFFEF2B2B)},
    ];

    return Row(
      children: options.map((opt) {
        final active = opt['value'] == value;
        final color = opt['color'] as Color;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChange(opt['value'] as Criticality),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: active ? color : AppColors.secondary,
                borderRadius: BorderRadius.circular(AppColors.radius),
                border: Border.all(
                  color: active ? color : AppColors.border,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    opt['label'] as String,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : AppColors.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
