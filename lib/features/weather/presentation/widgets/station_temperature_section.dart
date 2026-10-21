import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/weather_narrative.dart';
import '../providers/station_temperature_provider.dart';
import 'narrative_card.dart';

/// Temperature stories from nearby stations (mobile#299). Renders nothing
/// when signed out, without a location, while backgrounded, or while the
/// backend route is not deployed; an empty cell says so plainly.
class StationTemperatureSection extends ConsumerWidget {
  const StationTemperatureSection({super.key, this.onShare});

  final void Function(WeatherNarrative narrative)? onShare;

  /// Whether this section shows anything (used to keep the stories screen's
  /// own "No stories yet" view from hiding it).
  static bool isVisible(StationTemperatureStatus status) =>
      status == StationTemperatureStatus.ready ||
      status == StationTemperatureStatus.empty ||
      status == StationTemperatureStatus.unavailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stationTemperatureProvider);
    if (!isVisible(state.status)) return const SizedBox.shrink();

    final Widget body = switch (state.status) {
      StationTemperatureStatus.ready => Column(
        children: [
          for (final n in state.narratives)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NarrativeCard(
                narrative: n,
                onShare: onShare == null ? null : () => onShare!(n),
              ),
            ),
        ],
      ),
      StationTemperatureStatus.empty => const Text(
        'No recent station temperature data for your area yet.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      _ => const Text(
        'Station temperatures are unavailable right now.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.thermostat, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Nearby station temperatures',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}
