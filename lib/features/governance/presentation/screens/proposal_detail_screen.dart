import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../data/models/advisory_proposal.dart';
import '../providers/proposals_provider.dart';
import '../widgets/advisory_proposal_card.dart';
import '../widgets/advisory_vote_panel.dart';

/// One advisory proposal, read fresh by id. [initial] (the list's copy)
/// shows at once while the fresh read loads, and stays if it fails. An open
/// proposal gets the in-app vote panel (signed with the app's own wallet key).
class ProposalDetailScreen extends ConsumerWidget {
  const ProposalDetailScreen({
    super.key,
    required this.proposalId,
    this.initial,
  });

  final String proposalId;
  final AdvisoryProposal? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(advisoryProposalProvider(proposalId));
    final proposal = detail.value?.proposal ?? initial;
    final observed = detail.value?.observedAtHeight;

    return Scaffold(
      appBar: AppBar(title: Text(proposal?.title ?? 'Proposal')),
      body: proposal == null
          ? detail.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorWidget.fromFailure(
                e is Failure
                    ? e
                    : const ServerFailure("Couldn't load this proposal."),
                onRetry: () =>
                    ref.invalidate(advisoryProposalProvider(proposalId)),
              ),
              data: (_) => const SizedBox.shrink(),
            )
          : RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(advisoryProposalProvider(proposalId).future),
              child: _Body(
                proposal: proposal,
                observedAtHeight: observed,
                stale: detail.hasError,
              ),
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.proposal,
    required this.observedAtHeight,
    required this.stale,
  });

  final AdvisoryProposal proposal;
  final int? observedAtHeight;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    const muted = TextStyle(color: AppColors.textSecondary, fontSize: 12);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (stale)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              "Couldn't refresh this proposal; showing the list's copy. "
              'Pull down to try again.',
              style: TextStyle(color: AppColors.warning, fontSize: 13),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AdvisoryStatusChip(status: p.status),
                    const Spacer(),
                    Text(p.kind, style: muted),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  p.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (p.summary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(p.summary, style: const TextStyle(fontSize: 15)),
                ],
                const SizedBox(height: 12),
                if (p.proposer != null)
                  Text('Proposed by ${p.proposer}', style: muted),
                Text(
                  [
                    p.id,
                    if (p.createdAtBlock != null)
                      'proposed at block ${p.createdAtBlock}',
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Votes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                AdvisoryVoteSummary(proposal: p),
                if (p.eligibleCount != null) ...[
                  const SizedBox(height: 4),
                  Text('${p.eligibleCount} wallets could vote', style: muted),
                ],
                const SizedBox(height: 12),
                Text(
                  describeAdvisoryDeadline(p, observedAtHeight),
                  style: const TextStyle(fontSize: 14),
                ),
                if (observedAtHeight != null &&
                    p.finalizedAtBlock == null &&
                    p.votingDeadline != null)
                  Text(
                    'Estimated at about 77 s per block from block '
                    '$observedAtHeight.',
                    style: muted,
                  ),
              ],
            ),
          ),
        ),
        if (p.isActive) ...[
          const SizedBox(height: 12),
          AdvisoryVotePanel(proposal: p),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              advisoryDepositNote(p),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}
