import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../challenges/data/repositories/challenge_repository.dart';
import '../../../settings/presentation/widgets/settings_gear_button.dart';

/// The way in to everything that has no place on the navigation bar. Each
/// entry opens its existing route on top of this list, so the bar stays on
/// More and Back returns here.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same gate as the Challenges icon on Collect.
    final challenges = ref.watch(challengeCapabilityProvider).available;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ResponsiveListView(
        maxContentWidth: 760,
        children: [
          const _Group('Explore', [
            _Entry(Icons.link, 'Chain', '/wallet/chain'),
            _Entry(Icons.hub_outlined, 'Nodes', '/wallet/nodes'),
            _Entry(Icons.map, 'Weather map', '/weather/map'),
            _Entry(Icons.stars, 'Sky View', '/weather/ar'),
          ]),
          _Group('Forecasting', [
            const _Entry(
              Icons.fact_check_outlined,
              'Forecast check',
              '/weather/forecast-check',
            ),
            const _Entry(
              Icons.emoji_events_outlined,
              'Competitions',
              '/profile/competitions',
            ),
            const _Entry(Icons.sports_score, 'Duels', '/collect/duels'),
            if (challenges)
              const _Entry(
                Icons.groups_2_outlined,
                'Friend Challenges',
                '/collect/challenges',
              ),
            const _Entry(
              Icons.leaderboard,
              'Leaderboard',
              '/profile/leaderboard',
            ),
          ]),
          const _Group('Community', [
            _Entry(Icons.how_to_vote, 'Govern', '/govern'),
          ]),
          const Divider(),
          const _Entry(Icons.settings, 'Settings', SettingsGearButton.route),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.entries);

  final String title;
  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        ...entries,
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry(this.icon, this.label, this.route);

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
  }
}
