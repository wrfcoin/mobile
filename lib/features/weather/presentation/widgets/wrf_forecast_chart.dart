import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/wrf_forecast_model.dart';

/// Multi-line fl_chart visualising WRF model hourly forecasts.
///
/// Displays three series on the primary Y-axis (°C / m/s) and a secondary
/// Y-axis for precipitation (mm).  A shaded confidence band is drawn around
/// the temperature line.
///
/// Satisfies WCAG 2.1 SC 1.1.1 via [Semantics.label].
class WrfForecastChart extends StatelessWidget {
  final WrfForecastModel forecast;

  const WrfForecastChart({super.key, required this.forecast});

  @override
  Widget build(BuildContext context) {
    final points = forecast.hourly;

    if (points.isEmpty) {
      return const _EmptyChart();
    }

    // Build fl_chart spot lists.
    final tempSpots = <FlSpot>[];
    final tempHighSpots = <FlSpot>[];
    final tempLowSpots = <FlSpot>[];
    final precipSpots = <FlSpot>[];
    final windSpots = <FlSpot>[];

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = i.toDouble();
      tempSpots.add(FlSpot(x, p.temperatureC));
      tempHighSpots.add(FlSpot(x, p.temperatureMaxC));
      tempLowSpots.add(FlSpot(x, p.temperatureMinC));
      // Scale precipitation to primary axis space (×5) so it's legible.
      precipSpots.add(FlSpot(x, p.precipitationMm * 5));
      windSpots.add(FlSpot(x, p.windSpeedMs));
    }

    // Y-axis domain: cover temp + wind range comfortably.
    final allY = [...tempSpots.map((s) => s.y), ...windSpots.map((s) => s.y)];
    final minY = (allY.reduce((a, b) => a < b ? a : b) - 2).floorToDouble();
    final maxY = (allY.reduce((a, b) => a > b ? a : b) + 4).ceilToDouble();

    // X-axis labels: show every 6 hours.
    final xLabels = <int, String>{};
    for (var i = 0; i < points.length; i++) {
      if (i % 6 == 0) {
        final ts = DateTime.tryParse(points[i].timestamp);
        xLabels[i] = ts != null
            ? DateFormat('HHmm').format(ts.toLocal())
            : '$i';
      }
    }

    // Confidence band: ±1σ approximated by (maxC - minC) / 2.
    final chartData = LineChartData(
      minX: 0,
      maxX: (points.length - 1).toDouble(),
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: AppColors.border.withValues(alpha: 0.5),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
          left: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: 6,
            getTitlesWidget: (value, meta) {
              final label = xLabels[value.toInt()];
              if (label == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          axisNameWidget: const Text(
            '°C / m/s',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
          ),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) => Text(
              value.toStringAsFixed(0),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
        ),
        rightTitles: AxisTitles(
          axisNameWidget: const Text(
            'mm×5',
            style: TextStyle(color: Colors.blue, fontSize: 10),
          ),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              final mm = value / 5;
              return Text(
                mm.toStringAsFixed(1),
                style: const TextStyle(color: Colors.blue, fontSize: 10),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        // Confidence shading band — drawn as a filled area between max and min.
        LineChartBarData(
          spots: tempHighSpots,
          isCurved: true,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.red.withValues(alpha: 0.10),
            // Fill down to the min temperature line.
            cutOffY: tempLowSpots.isNotEmpty ? tempLowSpots.first.y : minY,
            applyCutOffY: false,
          ),
        ),
        LineChartBarData(
          spots: tempLowSpots,
          isCurved: true,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        ),
        // Temperature — red solid line.
        LineChartBarData(
          spots: tempSpots,
          isCurved: true,
          color: Colors.red,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
        // Precipitation (scaled ×5) — blue dashed line.
        LineChartBarData(
          spots: precipSpots,
          isCurved: true,
          color: Colors.blue,
          barWidth: 2,
          dashArray: [4, 4],
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
        // Wind speed — green line.
        LineChartBarData(
          spots: windSpots,
          isCurved: true,
          color: Colors.green,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.surface,
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final labels = ['Temp', 'Precip', 'Wind'];
              final idx = touchedSpots.indexOf(spot);
              final label = idx < labels.length ? labels[idx] : '';
              return LineTooltipItem(
                '$label: ${spot.y.toStringAsFixed(1)}',
                const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              );
            }).toList();
          },
        ),
      ),
    );

    return Semantics(
      label:
          'WRF forecast chart showing temperature, precipitation, and wind speed '
          'over the next ${points.length} hours. '
          '${forecast.isSimulated ? "Data is simulated." : "Data is live WRF model output."}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'WRF Model Forecast',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  WrfSimulatedBadge(isSimulated: forecast.isSimulated),
                ],
              ),
              const SizedBox(height: 4),
              _ChartLegend(),
              const SizedBox(height: 8),
              SizedBox(height: 200, child: LineChart(chartData)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Badge indicating whether WRF data is live or simulated.
/// Public so it can be shared with [HddCddCard].
class WrfSimulatedBadge extends StatelessWidget {
  final bool isSimulated;
  const WrfSimulatedBadge({super.key, required this.isSimulated});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isSimulated ? 'Data source: SIMULATED' : 'Data source: LIVE WRF',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSimulated
              ? AppColors.textMuted.withValues(alpha: 0.25)
              : AppColors.success.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSimulated
                ? AppColors.textMuted.withValues(alpha: 0.5)
                : AppColors.success.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          isSimulated ? 'SIMULATED' : 'LIVE (WRF)',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isSimulated ? AppColors.textSecondary : AppColors.success,
          ),
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _LegendDot(color: Colors.red, label: 'Temp (°C)'),
        SizedBox(width: 12),
        _LegendDot(color: Colors.blue, label: 'Precip (mm)'),
        SizedBox(width: 12),
        _LegendDot(color: Colors.green, label: 'Wind (m/s)'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 160,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.cloud_off, color: AppColors.textMuted, size: 40),
              SizedBox(height: 8),
              Text(
                'No WRF forecast data',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
