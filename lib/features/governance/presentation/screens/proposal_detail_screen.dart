import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../data/models/advisory_proposal.dart';
import '../providers/proposals_provider.dart';
import '../widgets/advisory_proposal_card.dart';

/// Opens a URL in the browser; [launchUrl] outside tests.
typedef UrlOpener = Future<bool> Function(Uri url, {LaunchMode mode});

/// One advisory proposal, read fresh by id. [initial] (the list's copy)
/// shows at once while the fresh read loads, and stays if it fails.
class ProposalDetailScreen extends ConsumerWidget {
  const ProposalDetailScreen({
    super.key,
    required this.proposalId,
    this.initial,
    this.openUrl = launchUrl,
  });

  final String proposalId;
  final AdvisoryProposal? initial;
  final UrlOpener openUrl;

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
                openUrl: openUrl,
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
    required this.openUrl,
  });

  final AdvisoryProposal proposal;
  final int? observedAtHeight;
  final bool stale;
  final UrlOpener openUrl;

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
        if (p.isActive) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('Vote on wrfcoin.com'),
            onPressed: () => _openVotePage(context),
          ),
          const SizedBox(height: 8),
          const Text(
            "The app can't sign advisory votes yet. Vote with your wallet on "
            'the website.',
            textAlign: TextAlign.center,
            style: muted,
          ),
        ],
      ],
    );
  }

  Future<void> _openVotePage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(advisoryVoteWebUrl);
    var opened = false;
    try {
      opened = await openUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('Vote page did not open: $error');
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Open $advisoryVoteWebUrl to vote.')),
      );
    }
  }
}
