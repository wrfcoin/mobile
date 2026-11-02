import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/weather_narratives_provider.dart';
import '../screens/weather_stories_screen.dart';
import 'narrative_card.dart';

/// Teaser card showing the latest 1-2 weather narratives with a
/// "See all" link to the full [WeatherStoriesScreen].
class WeatherStoryTeaser extends ConsumerWidget {
  const WeatherStoryTeaser({super.key});

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
