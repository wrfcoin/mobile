import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/role_earnings_model.dart';
import '../providers/role_earnings_provider.dart';

class RoleEarningsBoard extends ConsumerStatefulWidget {
  const RoleEarningsBoard({super.key});
  @override
  ConsumerState<RoleEarningsBoard> createState() => _RoleEarningsBoardState();
}

class _RoleEarningsBoardState extends ConsumerState<RoleEarningsBoard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(roleBoardProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roleBoardProvider);
    final notifier = ref.read(roleBoardProvider.notifier);
    final board = state.board;
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final role in EarningsRole.values)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: Text(role.label),
                    selected: state.role == role,
                    onSelected: (_) =>
                        notifier.load(role: role, period: EarningsPeriod.all),
                  ),
                ),
            ],
          ),
        ),
        if (state.role == EarningsRole.producer ||
            state.role == EarningsRole.attester)
          Wrap(
            children: [
              for (final period in EarningsPeriod.values)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: Text(period.label),
                    selected: state.period == period,
                    onSelected: (_) => notifier.load(period: period),
                  ),
                ),
            ],
          ),
        if (board?.coverage != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${state.period.label} payments · ${board!.coverage!.label}\nConfirmed canonical payments; totals may change after a rollback.',
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.failed || board?.status == EarningsStatus.unavailable
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Earnings unavailable right now'),
                      const Text('Paid-event coverage unavailable'),
                      TextButton(
                        onPressed: () => notifier.load(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : board?.status == EarningsStatus.unsupported
              ? const Center(
                  child: Text('Node payments are not implemented yet'),
                )
              : board == null
              ? const SizedBox.shrink()
              : board.rows.isEmpty
              ? Center(
                  child: Text(
                    state.role == EarningsRole.forecast
                        ? 'No forecast payments observed'
                        : 'No payments observed for this period',
                  ),
                )
              : ListView(
                  children: [
                    for (final row in board.rows)
                      ListTile(
                        leading: Text('#${row.rank}'),
                        title: Text(row.displayName),
                        subtitle: Text(
                          '${row.shortAddress}${row.isYou ? ' · You' : ''}',
                        ),
                        trailing: Text('${row.amount} WRF'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class OwnRoleEarningsSummary extends ConsumerWidget {
  const OwnRoleEarningsSummary({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(earningsReadProvider).asData?.value != true) {
      return const SizedBox.shrink();
    }
    final value = ref.watch(ownRoleEarningsProvider);
    return value.when(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Column(
        children: [
          const Text('Your role earnings are unavailable'),
          TextButton(
            onPressed: () => ref.invalidate(ownRoleEarningsProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
      data: (summary) => summary == null
          ? const SizedBox.shrink()
          : Column(
              children: [
                const Text(
                  'Your role payments · All time',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final role in summary.roles)
                  ListTile(
                    title: Text(role.role.label),
                    subtitle: Text(role.message),
                  ),
                Text(summary.coverage.label),
                const Text(
                  'Confirmed canonical payments; totals may change after a rollback.',
                ),
              ],
            ),
    );
  }
}
