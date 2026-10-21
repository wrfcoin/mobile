import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatting/app_formatters.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/proposal_model.dart';

class ProposalDetailScreen extends ConsumerWidget {
  final ProposalModel proposal;

  const ProposalDetailScreen({super.key, required this.proposal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalVotes =
        proposal.votesFor + proposal.votesAgainst + proposal.votesAbstain;
    final preferences = ref.watch(appPreferencesProvider).preferences;

    return Scaffold(
      appBar: AppBar(title: Text(proposal.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusChip(status: proposal.status),
                      const Spacer(),
                      Text(
                        proposal.proposalType,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    proposal.description,
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (proposal.createdAt != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Created: ${AppFormatters.formatIsoTimestamp(context, preferences, proposal.createdAt!)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Votes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _VoteBar(
                    label: 'For',
                    count: proposal.votesFor,
                    total: totalVotes,
                    color: AppColors.success,
                  ),
                  const SizedBox(height: 8),
                  _VoteBar(
                    label: 'Against',
                    count: proposal.votesAgainst,
                    total: totalVotes,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 8),
                  _VoteBar(
                    label: 'Abstain',
                    count: proposal.votesAbstain,
                    total: totalVotes,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total: $totalVotes votes',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (proposal.status == 'active')
            ElevatedButton(
              onPressed: () => context.push('/govern/vote', extra: proposal),
              child: const Text('Cast Your Vote'),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => AppColors.success,
      'passed' => AppColors.primary,
      'rejected' => AppColors.error,
      _ => AppColors.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _VoteBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _VoteBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? count / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('$count (${(fraction * 100).toStringAsFixed(1)}%)'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: fraction,
          backgroundColor: AppColors.surfaceLight,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ],
    );
  }
}
