import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Compact sparkline chart wrapping [fl_chart] LineChart.
///
/// Pass a list of [values] and an optional [color]. The chart auto-scales
/// vertically and distributes points evenly on the x-axis.
///
/// When [liveValue] is non-null it is appended to [values] and rendered with
/// a pulsing dot indicator at the rightmost point to signal a live data feed.
///
/// Wrapped in [RepaintBoundary] to isolate chart repaints from the rest of
/// the widget tree (animation performance — issue #53).
class SparklineChart extends StatefulWidget {
  final List<double> values;
  final Color? color;
  final double height;
  final bool showDots;
  final bool showArea;

  /// When non-null, appended as a live data point at the end of the chart
  /// with a pulsing animated indicator.
  final double? liveValue;

  const SparklineChart({
    super.key,
    required this.values,
    this.color,
    this.height = 48,
    this.showDots = false,
    this.showArea = true,
    this.liveValue,
  });

  @override
  State<SparklineChart> createState() => _SparklineChartState();
}

class _SparklineChartState extends State<SparklineChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.liveValue != null) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(SparklineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.liveValue != null && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (widget.liveValue == null && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allValues = [
      ...widget.values,
      if (widget.liveValue != null) widget.liveValue!,
    ];

    if (allValues.isEmpty) {
      return SizedBox(height: widget.height);
    }

    final lineColor = widget.color ?? AppColors.primary;
    final spots = <FlSpot>[];
    for (var i = 0; i < allValues.length; i++) {
      spots.add(FlSpot(i.toDouble(), allValues[i]));
    }

    final minY = allValues.reduce((a, b) => a < b ? a : b);
    final maxY = allValues.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.1;

    // Build dot data: regular dots for historical points, pulsing dot for live.
    final haslive = widget.liveValue != null;
    final lastIndex = allValues.length - 1;

    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, _) {
            return LineChart(
              LineChartData(
                minY: minY - padding,
                maxY: maxY + padding,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          spot.y.toStringAsFixed(1),
                          TextStyle(
                            color: lineColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: lineColor,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: widget.showDots || haslive,
                      getDotPainter: (spot, percent, barData, index) {
                        final isLivePoint = haslive && index == lastIndex;
                        final dotRadius = isLivePoint
                            ? 4.0 * _pulseAnimation.value
                            : 3.0;
                        final dotColor = isLivePoint
                            ? lineColor.withValues(alpha: _pulseAnimation.value)
                            : lineColor.withValues(alpha: 0.0);
                        return FlDotCirclePainter(
                          radius: isLivePoint
                              ? dotRadius
                              : (widget.showDots ? 2.5 : 0),
                          color: isLivePoint ? dotColor : lineColor,
                          strokeWidth: isLivePoint ? 2 : 0,
                          strokeColor: isLivePoint
                              ? lineColor.withValues(alpha: 0.5)
                              : Colors.transparent,
                        );
                      },
                    ),
                    belowBarData: widget.showArea
                        ? BarAreaData(
                            show: true,
                            color: lineColor.withValues(alpha: 0.12),
                          )
                        : BarAreaData(show: false),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 300),
            );
          },
        ),
      ),
    );
  }
}
