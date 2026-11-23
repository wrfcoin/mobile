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

  /// The latest observation (mobile#332). When present its temperature,
  /// humidity, wind and pressure are shown, null meaning "Not available";
  /// when absent (not loaded, or the call failed) the forecast's own values
  /// are used. The forecast period can be "Tonight" (the overnight low), so
  /// it must not stand in for the observed temperature when one exists.
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
    final temperatureC = current == null
        ? forecast.temperature
        : current.temperatureC;
    final windKmh = current == null ? forecast.windSpeed : current.windSpeedKmh;
    // Forecast fallback keeps its dash; an observation that lacks a reading
    // says so, like humidity and pressure.
    final missing = current == null ? '—' : notAvailable;
    // The time of the readings shown: the observation's when it is loaded
    // (its readings are on screen), else the forecast period's.
    final updatedAt = current == null ? forecast.timestamp : current.observedAt;

    // The big temperature leaves no room beside it at large text sizes.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final temperature = Text(
      temperatureC == null
          ? missing
          : AppFormatters.formatTemperature(context, preferences, temperatureC),
      // "Not available" at 48 would push the details off a phone screen.
      style: TextStyle(
        fontSize: temperatureC == null && current != null ? 20 : 48,
        fontWeight: FontWeight.bold,
      ),
    );
    final details = Column(
      children: [
        _DataRow(
          icon: Icons.water_drop,
          label: 'Humidity',
          value: humidity == null ? notAvailable : '${humidity.round()}%',
        ),
        const SizedBox(height: 8),
        _DataRow(
          icon: Icons.air,
          label: 'Wind',
          value: windKmh == null
              ? missing
              : AppFormatters.formatWindSpeed(context, preferences, windKmh),
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
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Side by side when they fit; a large text size wraps them.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
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
            ),
            const SizedBox(height: 16),
            stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      temperature,
                      const SizedBox(height: 16),
                      details,
                    ],
                  )
                : Row(
                    children: [
                      temperature,
                      const SizedBox(width: 24),
                      Expanded(child: details),
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
              value: updatedAt == null
                  ? notAvailable
                  : AppFormatters.formatIsoTimestamp(
                      context,
                      preferences,
                      updatedAt,
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
    // Label left and value right; a value too wide for that takes its own line.
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
