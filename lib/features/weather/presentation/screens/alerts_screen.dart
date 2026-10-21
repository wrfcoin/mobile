import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatting/app_formatters.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/errors/error_messages.dart';
import '../providers/weather_provider.dart';
import '../widgets/alerts_unavailable_card.dart';
import '../widgets/location_needed_card.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadIfUnanswered);
  }

  /// Opened before any alerts answer (e.g. from a notification, or while
  /// only the forecast refreshes): load once, rather than wait forever or
  /// show an empty list as all clear.
  void _loadIfUnanswered() {
    if (!mounted || _requested) return;
    final state = ref.read(weatherProvider);
    final answered =
        state.alertsLoaded || state.alertsError != null || state.locationNeeded;
    if (answered || state.loading || state.alertsLoading) return;
    _requested = true;
    ref.read(weatherProvider.notifier).loadLocalWeather();
  }

  @override
  Widget build(BuildContext context) {
    // Busy spans both halves of a load, so the gap between the forecast and
    // the alerts half does not look like a finished load.
    ref.listen(weatherProvider.select((s) => s.loading || s.alertsLoading), (
      previous,
      busy,
    ) {
      if (previous == true && !busy) _loadIfUnanswered();
    });
    final state = ref.watch(weatherProvider);
    final preferences = ref.watch(appPreferencesProvider).preferences;

    return Scaffold(
      appBar: AppBar(title: const Text('Weather Alerts')),
      // "All clear" only after a successful alerts response (#310's rule):
      // no location, a failed call, or no answer yet each say so instead.
      body: state.locationNeeded
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LocationNeededCard(
                  reason: state.locationUnavailable!,
                  onRetry: () =>
                      ref.read(weatherProvider.notifier).loadLocalWeather(),
                ),
              ),
            )
          : state.alertsError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AlertsUnavailableCard(
                  detail: ErrorMessages.fromFailure(state.alertsError!),
                  onRetry: () =>
                      ref.read(weatherProvider.notifier).loadLocalWeather(),
                ),
              ),
            )
          : !state.alertsLoaded
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : state.alerts.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: AppColors.success),
                  SizedBox(height: 16),
                  Text(
                    'No Active Alerts',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'All clear in your area',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.alerts.length,
              itemBuilder: (context, index) {
                final alert = state.alerts[index];
                final (severityColor, severityIcon) = switch (alert.severity
                    .toLowerCase()) {
                  'extreme' || 'severe' => (AppColors.error, Icons.warning),
                  'moderate' => (AppColors.warning, Icons.report_problem),
                  _ => (AppColors.textSecondary, Icons.info_outline),
                };

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(severityIcon, color: severityColor),
                    title: Text(alert.type),
                    subtitle: Text(
                      '${alert.description}\n${AppFormatters.formatIsoTimestamp(context, preferences, alert.timestamp)}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: severityColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        alert.severity.toUpperCase(),
                        style: TextStyle(
                          color: severityColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
