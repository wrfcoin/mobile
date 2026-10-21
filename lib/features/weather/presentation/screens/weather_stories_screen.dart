import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/weather_narrative.dart';
import '../providers/station_temperature_provider.dart';
import '../providers/weather_narratives_provider.dart';
import '../widgets/station_temperature_section.dart';
import '../widgets/narrative_card.dart';

/// Full-screen list of all weather narratives, grouped by type.
class WeatherStoriesScreen extends ConsumerWidget {
  const WeatherStoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final narrativeState = ref.watch(weatherNarrativesProvider);
    final narratives = narrativeState.narratives;
    final stationVisible = StationTemperatureSection.isVisible(
      ref.watch(stationTemperatureProvider).status,
    );

    // Group narratives by type
    final records = narratives
        .where((n) => n.type == NarrativeType.record)
        .toList();
    final events = narratives
        .where((n) => n.type == NarrativeType.event)
        .toList();
    final streaks = narratives
        .where((n) => n.type == NarrativeType.streak)
        .toList();
    final digests = narratives
        .where((n) => n.type == NarrativeType.digest)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Your Weather Story')),
      body: narrativeState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : narrativeState.error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  narrativeState.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          : narratives.isEmpty && !stationVisible
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_stories,
                    size: 64,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No stories yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start collecting weather data to build your story',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(weatherNarrativesProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Nearby station temperatures (mobile#299); hidden when
                  // signed out, without a location, or not deployed yet.
                  StationTemperatureSection(onShare: _shareNarrative),

                  // Summary header
                  if (narratives.isNotEmpty) ...[
                    _StorySummary(
                      totalNarratives: narratives.length,
                      recordCount: records.length,
                      eventCount: events.length,
                      streakCount: streaks.length,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Records section
                  if (records.isNotEmpty) ...[
                    _SectionHeader(
                      icon: Icons.emoji_events,
                      title: 'Personal Records',
                      color: const Color(0xFFFFD700),
                    ),
                    const SizedBox(height: 8),
                    ...records.map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: NarrativeCard(
                          narrative: n,
                          onShare: () => _shareNarrative(n),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Events section
                  if (events.isNotEmpty) ...[
                    _SectionHeader(
                      icon: Icons.thunderstorm,
                      title: 'Weather Events',
                      color: const Color(0xFF845EF7),
                    ),
                    const SizedBox(height: 8),
                    ...events.map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: NarrativeCard(
                          narrative: n,
                          onShare: () => _shareNarrative(n),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Streaks section
                  if (streaks.isNotEmpty) ...[
                    _SectionHeader(
                      icon: Icons.local_fire_department,
                      title: 'Collection Streaks',
                      color: const Color(0xFFFF6B6B),
                    ),
                    const SizedBox(height: 8),
                    ...streaks.map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: NarrativeCard(
                          narrative: n,
                          onShare: () => _shareNarrative(n),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Digests section
                  if (digests.isNotEmpty) ...[
                    _SectionHeader(
                      icon: Icons.summarize,
                      title: 'Weekly Digests',
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 8),
                    ...digests.map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: NarrativeCard(
                          narrative: n,
                          onShare: () => _shareNarrative(n),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  void _shareNarrative(WeatherNarrative narrative) {
    final provenance = narrative.provenance;
    if (provenance == null) return;
    SharePlus.instance.share(
      ShareParams(
        text:
            '${narrative.title}\n\n${narrative.description}\n\n'
            'Source: ${provenance.source} '
            '(${provenance.observationCount} persisted observations)',
      ),
    );
  }
}

class _StorySummary extends StatelessWidget {
  final int totalNarratives;
  final int recordCount;
  final int eventCount;
  final int streakCount;

  const _StorySummary({
    required this.totalNarratives,
    required this.recordCount,
    required this.eventCount,
    required this.streakCount,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_stories, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  '$totalNarratives Weather Stories',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryChip(
                  count: recordCount,
                  label: 'Records',
                  color: const Color(0xFFFFD700),
                ),
                _SummaryChip(
                  count: eventCount,
                  label: 'Events',
                  color: const Color(0xFF845EF7),
                ),
                _SummaryChip(
                  count: streakCount,
                  label: 'Streaks',
                  color: const Color(0xFFFF6B6B),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _SummaryChip({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
