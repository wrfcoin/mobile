import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/advisory_proposal.dart';

/// One advisory proposal in the list: title, status, yes/no against the
/// quorum, and the deadline (block plus an estimate).
class AdvisoryProposalCard extends StatelessWidget {
  const AdvisoryProposalCard({
    super.key,
    required this.proposal,
    this.observedAtHeight,
    this.onTap,
  });

  final AdvisoryProposal proposal;
  final int? observedAtHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AdvisoryStatusChip(status: p.status),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                p.title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (p.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  p.summary,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              AdvisoryVoteSummary(proposal: p),
              const SizedBox(height: 6),
              Text(
                describeAdvisoryDeadline(p, observedAtHeight),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "For 1 · Against 0" with how far the count is from the quorum.
class AdvisoryVoteSummary extends StatelessWidget {
  const AdvisoryVoteSummary({super.key, required this.proposal});

  final AdvisoryProposal proposal;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final yes = p.yesVotes;
    final no = p.noVotes;
    final cast = (yes ?? 0) + (no ?? 0);
    final quorum = p.quorumMinVotes;
    final approval = p.approvalPercent;
    final rules = <String>[
      if (quorum != null) 'needs $quorum votes',
      if (approval != null) '$approval% yes to pass',
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'For ${yes ?? '—'}',
              style: const TextStyle(color: AppColors.success, fontSize: 13),
            ),
            const Text(
              '  ·  ',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            Text(
              'Against ${no ?? '—'}',
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
        ),
        if (quorum != null && quorum > 0) ...[
          const SizedBox(height: 6),
          Semantics(
            label: '$cast of $quorum votes needed',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (cast / quorum).clamp(0.0, 1.0),
                backgroundColor: AppColors.surfaceLight,
                color: AppColors.primary,
                minHeight: 6,
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          [
            '$cast vote${cast == 1 ? '' : 's'} cast',
            if (rules.isNotEmpty) rules,
          ].join(' · '),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class AdvisoryStatusChip extends StatelessWidget {
  const AdvisoryStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => AppColors.success,
      'passed' => AppColors.primary,
      'rejected' => AppColors.error,
      _ => AppColors.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        advisoryStatusLabel(status).toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
