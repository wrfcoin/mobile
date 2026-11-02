import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/formatting/app_formatters.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/time/app_clock.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../data/models/forecast_detail_model.dart';
import '../providers/weather_provider.dart';
import 'condition_icon.dart';

/// Shown for an absent value.
const _absent = '—';

/// The hourly strip and daily list on the Weather tab: what WeatherState
/// already holds, so they cost no extra calls. Each says for itself when it is
/// loading or has nothing.
class ForecastSections extends ConsumerWidget {
  const ForecastSections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weatherProvider);
    final preferences = ref.watch(appPreferencesProvider).preferences;
    final now = ref.watch(appClockProvider)();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Hourly',
          onSeeAll: () =>
              context.push('/weather/forecast-detail', extra: state.forecast),
        ),
        _hourly(state, preferences, now, ref),
        const SizedBox(height: 12),
        const _SectionHeader(title: 'Daily'),
        _daily(state, preferences, now),
      ],
    );
  }

  Widget _hourly(
    WeatherState state,
    AppPreferences preferences,
    DateTime now,
    WidgetRef ref,
  ) {
    // Kept hours can age while offline: an hour that is over is not forecast.
    final hours = state.hourly?.where((hour) {
      final start = DateTime.tryParse(hour.timestamp);
      return start == null || start.add(const Duration(hours: 1)).isAfter(now);
    }).toList();
    if (hours != null && hours.isNotEmpty) {
      return _HourlyStrip(hours: hours, preferences: preferences);
    }
    if (state.hourlyLoading) {
      return const ShimmerList(count: 1, height: 120);
    }
    if (state.hourlyError != null) {
      return _SectionMessage(
        message: "Couldn't load the hourly forecast.",
        onRetry: () => ref.read(weatherProvider.notifier).retryHourly(),
      );
    }
    return const _SectionMessage(message: 'Hourly forecast not available.');
  }

  Widget _daily(WeatherState state, AppPreferences preferences, DateTime now) {
    final today = DateFormat('yyyy-MM-dd').format(now);
    final days = state.daily
        ?.where((day) => day.date.compareTo(today) >= 0)
        .toList();
    if (days == null || days.isEmpty) {
      return const _SectionMessage(message: 'Daily forecast not available.');
    }
    return Card(
      child: Column(
        children: [
          for (final (index, day) in days.indexed) ...[
            if (index > 0) const Divider(height: 1),
            _DailyRow(day: day, today: today, preferences: preferences),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Semantics(
                label: 'See the full forecast',
                excludeSemantics: true,
                child: const Text('See all'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionMessage extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _SectionMessage({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _HourlyStrip extends StatelessWidget {
  final List<HourlyForecast> hours;
  final AppPreferences preferences;

  const _HourlyStrip({required this.hours, required this.preferences});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final hour in hours)
              _HourTile(hour: hour, preferences: preferences),
          ],
        ),
      ),
    );
  }
}

class _HourTile extends StatelessWidget {
  final HourlyForecast hour;
  final AppPreferences preferences;

  const _HourTile({required this.hour, required this.preferences});

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(hour.timestamp);
    final temperature = hour.temperature;
    final wind = hour.windSpeed;
    final rain = hour.precipitationProbability;
    const small = TextStyle(fontSize: 11, color: AppColors.textSecondary);
    return SizedBox(
      width: 92,
      child: Card(
        margin: const EdgeInsets.only(right: 8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                start == null
                    ? _absent
                    : DateFormat.Hm().format(start.toLocal()),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  ConditionIcon(shortForecast: hour.shortForecast),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      temperature == null
                          ? _absent
                          : AppFormatters.formatTemperature(
                              context,
                              preferences,
                              temperature,
                            ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  hour.shortForecast ?? _absent,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
              ),
              const SizedBox(height: 4),
              if (rain != null)
                Text('Rain ${(rain * 100).round()}%', style: small),
              Text(
                wind == null
                    ? 'Wind $_absent'
                    : [
                        ?hour.windDirection,
                        AppFormatters.formatWindSpeed(
                          context,
                          preferences,
                          wind,
                        ),
                      ].join(' '),
                style: small,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyRow extends StatelessWidget {
  final DailyForecast day;
  final String today;
  final AppPreferences preferences;

  const _DailyRow({
    required this.day,
    required this.today,
    required this.preferences,
  });

  String _temperature(BuildContext context, double? celsius) => celsius == null
      ? _absent
      : AppFormatters.formatTemperature(context, preferences, celsius);

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse('${day.date}T12:00:00');
    final label = day.date == today
        ? 'Today'
        : date == null
        ? day.date
        : DateFormat('EEE, MMM d').format(date);
    final wind = day.windSpeed;
    final rain = day.precipitationProbability;
    final humidityMin = day.humidityMin;
    final humidityMax = day.humidityMax;
    final details = [
      if (rain != null) 'Rain ${(rain * 100).round()}%',
      if (wind != null)
        'Wind ${AppFormatters.formatWindSpeed(context, preferences, wind)}',
      if (humidityMin != null && humidityMax != null)
        humidityMin == humidityMax
            ? 'Humidity $humidityMin%'
            : 'Humidity $humidityMin\u2013$humidityMax%',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: ConditionIcon(shortForecast: day.shortForecast),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (day.shortForecast != null)
                  Text(
                    day.shortForecast!,
                    style: const TextStyle(fontSize: 13),
                  ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Low / high, as on the detail screen.
          Text(
            _temperature(context, day.tempMin),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const Text(' / '),
          Text(
            _temperature(context, day.tempMax),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
