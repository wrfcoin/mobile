import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../providers/weather_narratives_provider.dart';
import '../providers/weather_provider.dart';
import '../providers/wrf_forecast_provider.dart';
import '../screens/weather_stories_screen.dart';
import '../widgets/alerts_unavailable_card.dart';
import '../widgets/hdd_cdd_card.dart';
import '../widgets/location_needed_card.dart';
import '../widgets/narrative_card.dart';
import '../widgets/weather_card.dart';
import '../widgets/wrf_forecast_chart.dart';
import '../widgets/aqi_gauge.dart';

class ForecastDashboard extends ConsumerStatefulWidget {
  const ForecastDashboard({super.key});

  @override
  ConsumerState<ForecastDashboard> createState() => _ForecastDashboardState();
}

class _ForecastDashboardState extends ConsumerState<ForecastDashboard> {
  @override
  void initState() {
    super.initState();
    // No WRF request: the backend publishes no WRF output yet, so the WRF
    // section shows its unavailable card until a server response exists.
    Future.microtask(
      () => ref.read(weatherProvider.notifier).loadLocalWeather(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weatherProvider);
    final wrfState = ref.watch(wrfForecastProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather'),
        actions: [
          Semantics(
            button: true,
            label: 'Open weather map',
            child: IconButton(
              tooltip: 'Weather map',
              icon: const Icon(Icons.map),
              onPressed: () => context.push('/weather/map'),
            ),
          ),
          Semantics(
            button: true,
            label: 'Open forecast check',
            child: IconButton(
              tooltip: 'Forecast check',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () => context.push('/weather/forecast-check'),
            ),
          ),
          Semantics(
            button: true,
            label: 'Open weather alerts',
            child: IconButton(
              tooltip: 'Weather alerts',
              icon: const Icon(Icons.notifications),
              onPressed: () => context.push('/weather/alerts'),
            ),
          ),
        ],
      ),
      body: state.loading
          ? const ResponsiveCenter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Loading local forecast and alerts...',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  SizedBox(height: 16),
                  ShimmerList(count: 3, height: 120),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(weatherProvider.notifier).loadLocalWeather(),
              child: ResponsiveListView(
                maxContentWidth: 1040,
                children: [
                  // Offline cache banner
                  if (state.isFromCache)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.textMuted.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.wifi_off,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.cachedAt != null
                                  ? 'Offline — showing data cached at '
                                        '${_formatCacheTime(state.cachedAt!)}'
                                  : 'Offline — showing cached data',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Alert banner
                  if (state.alerts.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${state.alerts.length} active alert${state.alerts.length > 1 ? 's' : ''}',
                              style: const TextStyle(color: AppColors.warning),
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.push('/weather/alerts'),
                            child: const Text('View'),
                          ),
                        ],
                      ),
                    ),

                  // Failed alerts call: say so, rather than look like "no
                  // alerts" (review of #324, P2-3).
                  if (state.alertsError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.notifications_off,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AlertsUnavailableCard.title,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Current conditions
                  if (state.forecast != null) ...[
                    Semantics(
                      button: true,
                      label: 'View detailed forecast',
                      child: GestureDetector(
                        onTap: () => context.push(
                          '/weather/forecast-detail',
                          extra: state.forecast,
                        ),
                        child: WeatherCard(
                          forecast: state.forecast!,
                          current: state.current,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => context.push(
                          '/weather/forecast-detail',
                          extra: state.forecast,
                        ),
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: const Text('Hourly / Daily forecast'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // AQI
                    if (state.forecast!.aqi != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              AqiGauge(aqi: state.forecast!.aqi!),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Air Quality Index',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Based on real-time sensor data from the WRFCoin network.',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ] else if (state.locationNeeded)
                    LocationNeededCard(
                      reason: state.locationUnavailable!,
                      onRetry: () =>
                          ref.read(weatherProvider.notifier).loadLocalWeather(),
                    )
                  else if (state.error != null)
                    AppErrorWidget.fromFailure(
                      state.error!,
                      onRetry: () =>
                          ref.read(weatherProvider.notifier).loadLocalWeather(),
                    )
                  else
                    const Center(
                      child: Column(
                        children: [
                          Icon(Icons.cloud, size: 64, color: AppColors.primary),
                          SizedBox(height: 16),
                          Text(
                            'Pull to refresh weather data',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // WRF forecast section: server data only (mobile#269).
                  if (wrfState.data != null) ...[
                    _WrfBanner(isSimulated: wrfState.data!.isSimulated),
                    const SizedBox(height: 8),
                    WrfForecastChart(forecast: wrfState.data!),
                    const SizedBox(height: 8),
                    HddCddCard(forecast: wrfState.data!),
                    const SizedBox(height: 16),
                  ] else ...[
                    const WrfUnavailableCard(),
                    const SizedBox(height: 16),
                  ],

                  // Weather stories teaser
                  _WeatherStoryTeaser(),
                  const SizedBox(height: 16),

                  // Quick actions
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.stars,
                          label: 'Sky View',
                          onTap: () => context.push('/weather/ar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.tune,
                          label: 'Alert Settings',
                          onTap: () => context.push('/weather/alert-settings'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

String _formatCacheTime(DateTime dt) {
  return DateFormat('HH:mm').format(dt.toLocal());
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(icon, color: AppColors.primary, semanticLabel: label),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the WRF chart whenever no server response has been
/// received. Renders no forecast values.
class WrfUnavailableCard extends StatelessWidget {
  const WrfUnavailableCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: AppColors.textSecondary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'WRF model forecast unavailable. WRF model output is not being '
              'published on the testnet yet.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small banner stating whether a server WRF response is live or a
/// server-labelled simulation (payload `isSimulated`).
class _WrfBanner extends StatelessWidget {
  final bool isSimulated;
  const _WrfBanner({required this.isSimulated});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSimulated
            ? AppColors.textMuted.withValues(alpha: 0.10)
            : AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSimulated
              ? AppColors.border
              : AppColors.success.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSimulated ? Icons.science : Icons.satellite_alt,
            size: 14,
            color: isSimulated ? AppColors.textSecondary : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSimulated
                  ? 'WRF Model — SIMULATED data (per server)'
                  : 'WRF Model — LIVE output from IPFS pipeline',
              style: TextStyle(
                fontSize: 12,
                color: isSimulated
                    ? AppColors.textSecondary
                    : AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Teaser card showing the latest 1-2 weather narratives with a
/// "See all" link to the full [WeatherStoriesScreen].
class _WeatherStoryTeaser extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final narratives = ref.watch(weatherNarrativesProvider).narratives;
    if (narratives.isEmpty) return const SizedBox.shrink();

    final preview = narratives.take(2).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_stories,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Your Weather Story',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const WeatherStoriesScreen(),
                      ),
                    );
                  },
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...preview.map(
              (n) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: NarrativeCard(narrative: n),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
