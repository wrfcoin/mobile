import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/analytics_models.dart';

class AnalyticsTrendChart extends StatelessWidget {
  const AnalyticsTrendChart({
    super.key,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.lineColor,
    required this.valueSuffix,
  });

  final String title;
  final String subtitle;
  final List<AnalyticsTrendPoint> points;
  final Color lineColor;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return _EmptyTrendCard(title: title, subtitle: subtitle);
    }

    final sortedPoints = [...points]..sort((a, b) => a.day.compareTo(b.day));
    final maxY = sortedPoints
        .map((point) => point.value)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final safeMaxY = maxY <= 0 ? 1.0 : maxY * 1.15;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: safeMaxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: safeMaxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppColors.surfaceLight.withValues(alpha: 0.4),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: safeMaxY / 4,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(valueSuffix == ' WRF' ? 1 : 0),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: sortedPoints.length <= 4
                            ? 1
                            : (sortedPoints.length / 3).ceilToDouble(),
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (index < 0 || index >= sortedPoints.length) {
                            return const SizedBox.shrink();
                          }
                          final label = DateFormat('MMM d')
                              .format(sortedPoints[index].day);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                      color: AppColors.surfaceLight.withValues(alpha: 0.35),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (
                          var index = 0;
                          index < sortedPoints.length;
                          index++
                        )
                          FlSpot(index.toDouble(), sortedPoints[index].value),
                      ],
                      isCurved: true,
                      color: lineColor,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: lineColor.withValues(alpha: 0.18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TrendChip(
                  label: 'Latest',
                  value: _formatValue(sortedPoints.last.value),
                ),
                _TrendChip(label: 'Peak', value: _formatValue(maxY)),
                _TrendChip(label: 'Points', value: '${sortedPoints.length}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatValue(double value) {
    if (valueSuffix == ' WRF') {
      return '${value.toStringAsFixed(2)}$valueSuffix';
    }
    return '${value.toStringAsFixed(0)}$valueSuffix';
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTrendCard extends StatelessWidget {
  const _EmptyTrendCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 28),
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'No data yet',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
