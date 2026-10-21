import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Circular badge showing station uptime percentage.
///
/// Color coded: green (>=99%), yellow (>=95%), red (<95%).
class UptimeBadge extends StatelessWidget {
  final double uptimePercent;
  final double size;

  const UptimeBadge({super.key, required this.uptimePercent, this.size = 72});

  Color get _color {
    if (uptimePercent >= 99) return AppColors.success;
    if (uptimePercent >= 95) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final fraction = (uptimePercent / 100).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _UptimeArcPainter(
          fraction: fraction,
          color: _color,
          trackColor: Theme.of(context).colorScheme.surface,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${uptimePercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _color,
                  fontSize: size * 0.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'uptime',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: size * 0.12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UptimeArcPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color trackColor;

  _UptimeArcPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.08;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * fraction,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_UptimeArcPainter oldDelegate) =>
      fraction != oldDelegate.fraction || color != oldDelegate.color;
}
