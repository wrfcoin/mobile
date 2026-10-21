import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatting/app_formatters.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/current_conditions_model.dart';
import '../../data/models/forecast_model.dart';

class WeatherCard extends ConsumerWidget {
  /// Humidity and pressure are not in the backend's daily forecast periods
  /// (NOAA-NWS; mobile#270). Say so, rather than a bare dash that reads as a
  /// missing reading or a fabricated 0.
  static const notAvailable = 'Not available';

  final ForecastModel forecast;

  /// The latest observation (mobile#332). When present its humidity and
  /// pressure are shown, null meaning "Not available"; when absent (not
  /// loaded, or the call failed) the forecast's own values are used.
  final CurrentConditions? current;

  const WeatherCard({super.key, required this.forecast, this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesProvider).preferences;
    final current = this.current;
    final humidity = current == null
        ? forecast.humidity
        : current.relativeHumidityPercent;
    final pressure = current == null ? forecast.pressure : current.pressureHpa;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Current Conditions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  forecast.location,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  forecast.temperature == null
                      ? '—'
                      : AppFormatters.formatTemperature(
                          context,
                          preferences,
                          forecast.temperature!,
                        ),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: [
                      _DataRow(
                        icon: Icons.water_drop,
                        label: 'Humidity',
                        value: humidity == null
                            ? notAvailable
                            : '${humidity.round()}%',
                      ),
                      const SizedBox(height: 8),
                      _DataRow(
                        icon: Icons.air,
                        label: 'Wind',
                        value: forecast.windSpeed == null
                            ? '—'
                            : AppFormatters.formatWindSpeed(
                                context,
                                preferences,
                                forecast.windSpeed!,
                              ),
                      ),
                      const SizedBox(height: 8),
                      _DataRow(
                        icon: Icons.compress,
                        label: 'Pressure',
                        value: pressure == null
                            ? notAvailable
                            : AppFormatters.formatPressure(
                                context,
                                preferences,
                                pressure,
                                fractionDigits: 0,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (forecast.precipitation != null &&
                forecast.precipitation! > 0) ...[
              const Divider(height: 24),
              _DataRow(
                icon: Icons.umbrella,
                label: 'Precipitation',
                value: AppFormatters.formatPrecipitation(
                  context,
                  preferences,
                  forecast.precipitation!,
                ),
              ),
            ],
            const Divider(height: 24),
            _DataRow(
              icon: Icons.schedule,
              label: 'Updated',
              value: AppFormatters.formatIsoTimestamp(
                context,
                preferences,
                forecast.timestamp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DataRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
