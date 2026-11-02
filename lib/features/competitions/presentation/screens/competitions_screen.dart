import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/network/public_read.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/public_read_widgets.dart';
import '../../data/models/competition_model.dart';
import '../providers/competition_provider.dart';

const _forecastingGuide =
    'https://github.com/wrfcoin/docs/blob/main/testnet/forecasting.md';

const _statusLabels = <String, String>{
  'open': 'Open',
  'scoring': 'Counting',
  'final': 'Final',
};

String _status(String? status) =>
    _statusLabels[status] ?? status ?? publicUnknown;

/// A UTC calendar day: weeks are UTC weeks, so a local zone must not shift one.
String _utcDay(DateTime day) => DateFormat('MMM d').format(day.toUtc());

/// "Oct 26 – Nov 1". `until` is exclusive (next Monday 00:00 UTC), so it shows
/// the Sunday the week ends on.
String _weekRange(String? from, String? until) {
  final start = from == null ? null : DateTime.tryParse(from);
  final end = until == null ? null : DateTime.tryParse(until);
  final last = end?.subtract(const Duration(milliseconds: 1));
  return '${start == null ? publicUnknown : _utcDay(start)} – ${last == null ? publicUnknown : _utcDay(last)}';
}

/// The weekly forecast competition: points only, from the same routes as the
/// website's /competitions page. Every forecast the chain scores earns a point.
/// No entry form, no stake and no prize.
class CompetitionsScreen extends ConsumerStatefulWidget {
  const CompetitionsScreen({super.key});

  @override
  ConsumerState<CompetitionsScreen> createState() => _CompetitionsScreenState();
}

class _CompetitionsScreenState extends ConsumerState<CompetitionsScreen> {
  /// Null is this week.
  String? _week;

  void _reload() {
    ref.invalidate(competitionWeeksProvider);
    ref.invalidate(competitionStandingsProvider(_week));
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final weeksRead = ref.watch(competitionWeeksProvider).value;
    final list = weeksRead is PublicLoaded<CompetitionList>
        ? weeksRead.data
        : null;
    final standings = ref.watch(competitionStandingsProvider(_week));

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly competition')),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await ref.read(competitionStandingsProvider(_week).future);
        },
        child: ResponsiveListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              'Every forecast the chain scores this week earns a point. No entry form and nothing to stake: if you forecast on the testnet, you are in. Points only, no prizes.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
            if (list != null && list.weeks.isNotEmpty) ...[
              const SizedBox(height: 12),
              _WeekChips(
                list: list,
                selected: _week,
                onSelected: (week) => setState(() => _week = week),
              ),
            ],
            const SizedBox(height: 12),
            ...standings.when(
              loading: () => [
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(
                  'Loading standings…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ],
              // The repository does not throw; this is a last resort.
              error: (_, _) => [_unavailableCard()],
              data: (read) => switch (read) {
                PublicLoaded(:final data) => [
                  _Loaded(standings: data, thisWeek: _week == null),
                ],
                PublicNotFound() => const [
                  PublicNoticeCard(
                    icon: Icons.info_outline,
                    title: 'No competition for that week on this chain.',
                  ),
                ],
                PublicRateLimited() => [
                  PublicNoticeCard(
                    icon: Icons.hourglass_empty,
                    title: 'Too many requests. Please wait a moment and try again.',
                    onRetry: _reload,
                  ),
                ],
                PublicUnavailable(:final statusCode) when statusCode == 503 => [
                  PublicNoticeCard(
                    icon: Icons.cloud_off,
                    title: 'Forecast competitions are not available on this network yet',
                    message: 'The chain-reward index that feeds them is not running.',
                    onRetry: _reload,
                  ),
                ],
                PublicUnavailable() => [_unavailableCard()],
              },
            ),
            if (list != null) ...[
              const SizedBox(height: 12),
              _PastWeeks(
                list: list,
                onPick: (week) => setState(() => _week = week),
              ),
            ],
            const SizedBox(height: 12),
            const PublicLinkRow(
              label: 'Start forecasting',
              url: _forecastingGuide,
            ),
          ],
        ),
      ),
    );
  }

  Widget _unavailableCard() => PublicNoticeCard(
    icon: Icons.cloud_off,
    title: 'Forecast competitions unavailable right now.',
    onRetry: _reload,
  );
}

class _WeekChips extends StatelessWidget {
  const _WeekChips({
    required this.list,
    required this.selected,
    required this.onSelected,
  });

  final CompetitionList list;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final current = list.current;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final week in list.weeks)
          ChoiceChip(
            label: Text(
              week.week == current
                  ? 'This week'
                  : competitionWeekNumber(week.week),
            ),
            selected: (selected ?? current) == week.week,
            onSelected: (_) =>
                onSelected(week.week == current ? null : week.week),
          ),
      ],
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.standings, required this.thisWeek});

  final CompetitionStandings standings;
  final bool thisWeek;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final s = standings;
    final left = s.status == 'open' ? competitionTimeLeft(s.until) : null;
    final below = s.youBelow;
    final rule = s.rule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PublicStatGrid(
          stats: [
            (
              competitionWeekNumber(s.week),
              _weekRange(s.from, s.until),
              AppColors.primary,
            ),
            (
              'Status',
              left != null ? 'Ends in $left' : _status(s.status),
              s.status == 'final' ? AppColors.success : AppColors.primaryDark,
            ),
            ('Forecasters', publicCount(s.entrants), AppColors.secondary),
            ('Forecasts scored', publicCount(s.forecasts), AppColors.success),
          ],
        ),
        const SizedBox(height: 12),
        PublicSectionCard(
          title:
              '${thisWeek ? 'This week' : competitionWeekNumber(s.week)} · standings',
          count: '${s.rows.length} shown',
          children: [
            if (s.rows.isEmpty) ...[
              Text(
                thisWeek
                    ? 'No points yet this week'
                    : 'No scored forecasts that week',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                thisWeek
                    ? 'The first forecast the chain scores this week takes the lead. Forecasting is open to anyone with a wallet.'
                    : 'Nobody had a forecast scored in that week.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ] else ...[
              for (final row in s.rows) _StandingRow(row: row),
              if (below != null) _StandingRow(row: below),
            ],
            const SizedBox(height: 8),
            Text(
              s.isFinal
                  ? 'Final, read through block ${publicCount(s.finalThroughHeight)} · ${publicWhen(s.finalizedAt)}'
                  : 'Live as of block ${publicCount(s.asOfHeight)} · ${publicWhen(s.asOfTime)}',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            Text(
              'Addresses are shortened for visitors; sign in to your wallet to see your own.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
        if (rule != null) ...[
          const SizedBox(height: 12),
          PublicSectionCard(
            title: 'How points work',
            children: [
              // The backend's rule text, verbatim.
              for (final line in [rule.points, rule.ties, rule.week])
                if (line != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(line, style: const TextStyle(fontSize: 13)),
                  ),
              if (rule.prizes != null)
                Text(
                  rule.prizes!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.row});

  final CompetitionRow row;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final rank = row.rank;
    final top = rank != null && rank <= 3;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              rank == null ? publicUnknown : '#$rank',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: top ? AppColors.primary : muted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.shownAddress ?? publicUnknown,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (row.isYou) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'You',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${publicCount(row.forecasts)} forecasts · last ${publicWhen(row.lastAt)}',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${publicCount(row.points)} pts',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PastWeeks extends StatelessWidget {
  const _PastWeeks({required this.list, required this.onPick});

  final CompetitionList list;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final past = list.weeks.where((w) => w.week != list.current).toList();
    if (past.isEmpty) return const SizedBox.shrink();
    return PublicSectionCard(
      title: 'Past weeks',
      children: [
        for (final week in past)
          InkWell(
            onTap: () => onPick(week.week),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${competitionWeekNumber(week.week)} · ${_weekRange(week.from, week.until)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          week.leaders.isEmpty
                              ? 'No scored forecasts'
                              : '${week.status == 'final' ? 'Winner' : 'Leading'} ${week.leaders.first.shownAddress ?? publicUnknown} · ${publicCount(week.leaders.first.points)} pts',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _status(week.status),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
