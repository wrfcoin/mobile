import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/proposal_model.dart';

class ProposalCard extends StatelessWidget {
  final ProposalModel proposal;
  final VoidCallback? onTap;

  const ProposalCard({super.key, required this.proposal, this.onTap});

  @override
  Widget build(BuildContext context) {
    final totalVotes =
        proposal.votesFor + proposal.votesAgainst + proposal.votesAbstain;
    final forPercent = totalVotes > 0 ? proposal.votesFor / totalVotes : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                  _StatusChip(status: proposal.status),
                  const SizedBox(width: 8),
                  _TypeChip(type: proposal.proposalType),
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
                proposal.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                proposal.description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              // Vote progress bar
              Semantics(
                label: 'For votes ${(forPercent * 100).round()} percent',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: forPercent,
                    backgroundColor: AppColors.surfaceLight,
                    color: AppColors.success,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'For: ${proposal.votesFor}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Against: ${proposal.votesAgainst}',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Abstain: ${proposal.votesAbstain}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case 'active':
        color = AppColors.success;
      case 'passed':
        color = AppColors.primary;
      case 'rejected':
        color = AppColors.error;
      case 'pending':
        color = AppColors.warning;
      default:
        color = AppColors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type,
        style: const TextStyle(
          color: AppColors.secondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
