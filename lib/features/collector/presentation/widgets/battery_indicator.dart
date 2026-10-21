import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class BatteryIndicator extends StatelessWidget {
  final int level;

  const BatteryIndicator({super.key, required this.level});

  Color get _color {
    if (level <= 15) return AppColors.error;
    if (level <= 30) return AppColors.warning;
    return AppColors.success;
  }

  IconData get _icon {
    if (level <= 15) return Icons.battery_alert;
    if (level <= 30) return Icons.battery_3_bar;
    if (level <= 60) return Icons.battery_4_bar;
    return Icons.battery_full;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon, color: _color, size: 20),
        const SizedBox(width: 4),
        Text(
          '$level%',
          style: TextStyle(
            color: _color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
