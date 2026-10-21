import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class AqiGauge extends StatelessWidget {
  final int aqi;

  const AqiGauge({super.key, required this.aqi});

  Color get _color {
    if (aqi <= 50) return AppColors.success;
    if (aqi <= 100) return AppColors.warning;
    if (aqi <= 150) return Colors.orange;
    if (aqi <= 200) return AppColors.error;
    return AppColors.secondary; // purple for 201+
  }

  String get _label {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy\n(Sensitive)';
    if (aqi <= 200) return 'Unhealthy';
    return 'Very\nUnhealthy';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
        painter: _AqiPainter(aqi: aqi, color: _color),
        child: Center(
          child: Semantics(
            label: 'Air quality index $aqi, $_label',
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$aqi',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _color,
                  ),
                ),
                Text(
                  _label,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AqiPainter extends CustomPainter {
  final int aqi;
  final Color color;

  _AqiPainter({required this.aqi, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Background arc
    final bgPaint = Paint()
      ..color = AppColors.surfaceLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final sweep = (aqi.clamp(0, 500) / 500) * math.pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      sweep,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AqiPainter oldDelegate) =>
      aqi != oldDelegate.aqi || color != oldDelegate.color;
}
