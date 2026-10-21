import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/formatting/app_formatters.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../data/models/forecast_detail_model.dart';
import '../../data/models/forecast_model.dart';
import '../providers/forecast_detail_provider.dart';
import '../widgets/forecast_share_action.dart';
import '../widgets/location_needed_card.dart';

/// Forecast detail screen showing hourly (next 24 h) and 7-day breakdown,
/// from the backend's NOAA forecast (mobile#270). Values the forecast does
/// not carry are shown as absent, and a half that is not available says so
/// instead of failing the whole screen.
///
/// The screen is reachable via `/weather/forecast-detail`.  A current-conditions
/// [ForecastModel] can be passed as `extra` from the parent route so that we
/// have something to display while the detail loads.
class ForecastDetailScreen extends ConsumerStatefulWidget {
  final ForecastModel? currentForecast;

  const ForecastDetailScreen({super.key, this.currentForecast});

  @override
  ConsumerState<ForecastDetailScreen> createState() =>
      _ForecastDetailScreenState();
}

class _ForecastDetailScreenState extends ConsumerState<ForecastDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(
      () => ref.read(forecastDetailProvider.notifier).loadLocal(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(forecastDetailProvider);
    final preferences = ref.watch(appPreferencesProvider).preferences;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.currentForecast?.location ?? 'Forecast Detail'),
        actions: [
          // mobile#254: the share-ready weather card was fully built but had
          // no route to a user; this is its call site.
          if (widget.currentForecast != null)
            ForecastShareAction(forecast: widget.currentForecast!),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.access_time), text: 'Hourly'),
            Tab(icon: Icon(Icons.calendar_month), text: '7-Day'),
          ],
        ),
      ),
      body: state.loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: ShimmerList(count: 8, height: 72),
            )
          : state.locationNeeded
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LocationNeededCard(
                  reason: state.locationUnavailable!,
                  onRetry: () =>
                      ref.read(forecastDetailProvider.notifier).loadLocal(),
                ),
              ),
            )
          : state.error != null && state.detail == null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: AppErrorWidget.fromFailure(
                state.error!,
                onRetry: () =>
                    ref.read(forecastDetailProvider.notifier).loadLocal(),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _HourlyTab(
                  hourly: state.detail?.hourly ?? const [],
                  preferences: preferences,
                ),
                _DailyTab(
                  daily: state.detail?.daily ?? const [],
                  preferences: preferences,
                ),
              ],
            ),
    );
  }
}

// ── Hourly tab ─────────────────────────────────────────────────────────────

/// Shown for an absent value.
const _absent = '—';

class _HourlyTab extends StatelessWidget {
  final List<HourlyForecast> hourly;
  final AppPreferences preferences;

  const _HourlyTab({required this.hourly, required this.preferences});

  @override
  Widget build(BuildContext context) {
    if (hourly.isEmpty) {
      return const _EmptyState(message: 'Hourly forecast not available yet');
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: hourly.length,
      separatorBuilder: (context, separatorIndex) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) =>
          _HourlyTile(slot: hourly[index], preferences: preferences),
    );
  }
}

class _HourlyTile extends StatelessWidget {
  final HourlyForecast slot;
  final AppPreferences preferences;

  const _HourlyTile({required this.slot, required this.preferences});

  @override
  Widget build(BuildContext context) {
    final ts = DateTime.tryParse(slot.timestamp);
    final timeLabel = ts != null ? DateFormat.Hm().format(ts.toLocal()) : '--';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SizedBox(
        width: 52,
        child: Center(
          child: Text(
            timeLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            _temperature(context, preferences, slot.temperature),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(width: 8),
          _ConditionIcon(shortForecast: slot.shortForecast),
          if (slot.shortForecast != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                slot.shortForecast!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          'Humidity ${_percent(slot.humidity)}',
          'Wind ${_wind(context, preferences, slot.windSpeed)}',
        ].join('  ·  '),
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: slot.precipitationProbability != null
          ? _PrecipChip(probability: slot.precipitationProbability!)
          : null,
    );
  }
}

String _temperature(
  BuildContext context,
  AppPreferences preferences,
  double? celsius,
) => celsius == null
    ? _absent
    : AppFormatters.formatTemperature(context, preferences, celsius);

String _wind(BuildContext context, AppPreferences preferences, double? kmh) =>
    kmh == null
    ? _absent
    : AppFormatters.formatWindSpeed(context, preferences, kmh);

String _percent(double? value) => value == null ? _absent : '${value.round()}%';

// ── Daily tab ──────────────────────────────────────────────────────────────

class _DailyTab extends StatelessWidget {
  final List<DailyForecast> daily;
  final AppPreferences preferences;

  const _DailyTab({required this.daily, required this.preferences});

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return const _EmptyState(message: '7-day forecast not available yet');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: daily.length,
      itemBuilder: (context, index) =>
          _DailyCard(day: daily[index], preferences: preferences),
    );
  }
}

class _DailyCard extends StatelessWidget {
  final DailyForecast day;
  final AppPreferences preferences;

  const _DailyCard({required this.day, required this.preferences});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse('${day.date}T12:00:00');
    final dateLabel = date != null
        ? DateFormat('EEE, MMM d').format(date)
        : day.date;
    final isToday =
        date != null &&
        DateFormat('yyyy-MM-dd').format(date) ==
            DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    isToday ? 'Today' : dateLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isToday
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                _ConditionIcon(shortForecast: day.shortForecast),
                const Spacer(),
                // Low / high
                Text(
                  _temperature(context, preferences, day.tempMin),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(width: 4),
                const Text('/'),
                const SizedBox(width: 4),
                Text(
                  _temperature(context, preferences, day.tempMax),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (day.shortForecast != null) ...[
              const SizedBox(height: 4),
              Text(day.shortForecast!, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (day.humidityMin != null && day.humidityMax != null)
                  _SmallStat(
                    icon: Icons.water_drop,
                    label: day.humidityMin == day.humidityMax
                        ? 'Humidity ${day.humidityMin}%'
                        : 'Humidity ${day.humidityMin}\u2013${day.humidityMax}%',
                  ),
                _SmallStat(
                  icon: Icons.air,
                  label: 'Wind ${_wind(context, preferences, day.windSpeed)}',
                ),
                if (day.precipitationProbability != null)
                  _SmallStat(
                    icon: Icons.umbrella,
                    label: _percent(day.precipitationProbability! * 100),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

class _ConditionIcon extends StatelessWidget {
  final String? shortForecast;

  const _ConditionIcon({required this.shortForecast});

  @override
  Widget build(BuildContext context) {
    final text = shortForecast?.toLowerCase() ?? '';
    final icon = switch (text) {
      _ when text.contains('thunder') => Icons.thunderstorm,
      _ when text.contains('snow') || text.contains('sleet') => Icons.ac_unit,
      _
          when text.contains('rain') ||
              text.contains('shower') ||
              text.contains('drizzle') =>
        Icons.grain,
      _ when text.contains('fog') || text.contains('haze') => Icons.blur_on,
      _ when text.contains('partly') => Icons.wb_cloudy,
      _ when text.contains('cloud') || text.contains('overcast') => Icons.cloud,
      _ when text.contains('sunny') || text.contains('clear') => Icons.wb_sunny,
      _ when text.contains('wind') || text.contains('breezy') => Icons.air,
      _ => Icons.help_outline,
    };
    return Icon(icon, size: 18, color: AppColors.primary);
  }
}

class _PrecipChip extends StatelessWidget {
  final double probability;

  const _PrecipChip({required this.probability});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.umbrella, size: 14, color: Colors.blue),
      label: Text(
        '${(probability * 100).round()}%',
        style: const TextStyle(fontSize: 12),
      ),
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.only(right: 6),
      backgroundColor: Colors.blue.withValues(alpha: 0.12),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SmallStat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SmallStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
