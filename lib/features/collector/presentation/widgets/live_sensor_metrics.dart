import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/sensor_stream_provider.dart';

/// 2×2 animated grid showing live device sensor readings.
///
/// Watches [sensorStreamProvider] and animates value changes with an
/// [AnimatedSwitcher]. Each tile has a colored trend indicator (↑/↓ + delta)
/// relative to the previous reading.
class LiveSensorMetrics extends ConsumerStatefulWidget {
  const LiveSensorMetrics({super.key});

  @override
  ConsumerState<LiveSensorMetrics> createState() => _LiveSensorMetricsState();
}

class _LiveSensorMetricsState extends ConsumerState<LiveSensorMetrics> {
  SensorSnapshot? _previous;

  @override
  Widget build(BuildContext context) {
    final asyncSnap = ref.watch(sensorStreamProvider);

    return asyncSnap.when(
      loading: () => const _MetricsLoadingPlaceholder(),
      error: (error, stack) => const _MetricsErrorPlaceholder(),
      data: (snapshot) {
        final prev = _previous;
        // Update previous after the frame to capture trends.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _previous = snapshot);
          }
        });

        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: [
            _MetricTile(
              label: 'Temperature',
              value: snapshot.temperature != null
                  ? snapshot.temperature!.toStringAsFixed(1)
                  : '--',
              unit: '°C',
              previousValue: prev?.temperature,
              currentValue: snapshot.temperature,
              semanticLabel: snapshot.temperature != null
                  ? 'Temperature ${snapshot.temperature!.toStringAsFixed(1)} degrees Celsius'
                  : 'Temperature unavailable',
              icon: Icons.thermostat,
              iconColor: Colors.orange,
            ),
            _MetricTile(
              label: 'Humidity',
              value: snapshot.humidity != null
                  ? snapshot.humidity!.toStringAsFixed(0)
                  : '--',
              unit: '%',
              previousValue: prev?.humidity,
              currentValue: snapshot.humidity,
              semanticLabel: snapshot.humidity != null
                  ? 'Humidity ${snapshot.humidity!.toStringAsFixed(0)} percent'
                  : 'Humidity unavailable',
              icon: Icons.water_drop,
              iconColor: Colors.blue,
            ),
            _MetricTile(
              label: 'Pressure',
              value: snapshot.pressure != null
                  ? snapshot.pressure!.toStringAsFixed(1)
                  : '--',
              unit: 'hPa',
              previousValue: prev?.pressure,
              currentValue: snapshot.pressure,
              semanticLabel: snapshot.pressure != null
                  ? 'Pressure ${snapshot.pressure!.toStringAsFixed(1)} hectopascals'
                  : 'Pressure unavailable',
              icon: Icons.speed,
              iconColor: AppColors.primary,
            ),
            _MetricTile(
              label: 'Battery',
              value: snapshot.batteryLevel >= 0
                  ? snapshot.batteryLevel.toString()
                  : '--',
              unit: '%',
              previousValue: prev != null && prev.batteryLevel >= 0
                  ? prev.batteryLevel.toDouble()
                  : null,
              currentValue: snapshot.batteryLevel >= 0
                  ? snapshot.batteryLevel.toDouble()
                  : null,
              semanticLabel: snapshot.batteryLevel >= 0
                  ? 'Battery ${snapshot.batteryLevel} percent'
                  : 'Battery unavailable',
              icon: _batteryIcon(snapshot.batteryLevel),
              iconColor: _batteryColor(snapshot.batteryLevel),
            ),
          ],
        );
      },
    );
  }

  IconData _batteryIcon(int level) {
    if (level < 0) return Icons.battery_unknown;
    if (level <= 20) return Icons.battery_1_bar;
    if (level <= 40) return Icons.battery_2_bar;
    if (level <= 60) return Icons.battery_3_bar;
    if (level <= 80) return Icons.battery_4_bar;
    return Icons.battery_full;
  }

  Color _batteryColor(int level) {
    if (level < 0) return AppColors.textSecondary;
    if (level <= 20) return AppColors.error;
    if (level <= 40) return AppColors.warning;
    return AppColors.success;
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final double? previousValue;
  final double? currentValue;
  final String semanticLabel;
  final IconData icon;
  final Color iconColor;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.previousValue,
    required this.currentValue,
    required this.semanticLabel,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final trend = _computeTrend();

    return Semantics(
      label: semanticLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: iconColor),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: Text(
                      value,
                      key: ValueKey<String>(value),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      unit,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (trend != null) _TrendIndicator(trend: trend),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _Trend? _computeTrend() {
    if (previousValue == null || currentValue == null) return null;
    final delta = currentValue! - previousValue!;
    if (delta.abs() < 0.01) return null;
    return _Trend(delta: delta, isUp: delta > 0);
  }
}

class _Trend {
  final double delta;
  final bool isUp;

  const _Trend({required this.delta, required this.isUp});
}

class _TrendIndicator extends StatelessWidget {
  final _Trend trend;

  const _TrendIndicator({required this.trend});

  @override
  Widget build(BuildContext context) {
    final color = trend.isUp ? AppColors.success : AppColors.error;
    final icon = trend.isUp ? Icons.arrow_upward : Icons.arrow_downward;
    final label = '${trend.isUp ? "+" : ""}${trend.delta.toStringAsFixed(1)}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MetricsLoadingPlaceholder extends StatelessWidget {
  const _MetricsLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 100,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _MetricsErrorPlaceholder extends StatelessWidget {
  const _MetricsErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 60,
      child: Center(
        child: Text(
          'Sensor data unavailable',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }
}
