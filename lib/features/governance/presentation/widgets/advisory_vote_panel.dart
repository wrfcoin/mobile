import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/crypto/advisory_action_signing.dart';
import '../../../../services/crypto/transfer_signing_domain.dart';
import '../../data/models/advisory_proposal.dart';
import '../../data/models/advisory_vote.dart';
import '../../data/repositories/governance_repository_impl.dart';
import '../providers/proposals_provider.dart';

/// Vote For / Against on an open advisory proposal with the app's own wallet
/// key. Checks eligibility first and says plainly why a wallet can't vote. A
/// confirm sheet shows exactly what is signed; the device unlock (the same
/// gate a send uses) opens the key. The recovery phrase is never asked for.
class AdvisoryVotePanel extends ConsumerStatefulWidget {
  const AdvisoryVotePanel({
    super.key,
    required this.proposal,
    this.refreshAfter = const Duration(seconds: 90),
  });

  final AdvisoryProposal proposal;

  /// After a vote is sent, the proposal is read again now and once more
  /// after this delay (about one block plus margin).
  final Duration refreshAfter;

  @override
  ConsumerState<AdvisoryVotePanel> createState() => _AdvisoryVotePanelState();
}

class _AdvisoryVotePanelState extends ConsumerState<AdvisoryVotePanel> {
  bool _busy = false;
  bool _sent = false;

  /// True when the relay's answer was lost: the vote may still count.
  bool _uncertain = false;
  String? _error;
  Timer? _later;

  @override
  void dispose() {
    _later?.cancel();
    super.dispose();
  }

  void _refresh(String address) {
    final id = widget.proposal.id;
    ref.invalidate(advisoryProposalProvider(id));
    ref.invalidate(advisoryEligibilityProvider((id, address)));
    ref.invalidate(advisoryProposalsProvider);
  }

  Future<void> _vote(String address, bool approve) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AdvisoryVoteConfirmSheet(
        proposal: widget.proposal,
        approve: approve,
        address: address,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _uncertain = false;
    });
    final result = await ref
        .read(governanceRepositoryProvider)
        .voteAdvisory(
          proposalId: widget.proposal.id,
          approve: approve,
          createdAtBlock: widget.proposal.createdAtBlock,
        );
    if (!mounted) return;
    void watchChain() {
      _refresh(address);
      _later?.cancel();
      _later = Timer(widget.refreshAfter, () {
        if (mounted) _refresh(address);
      });
    }

    result.match(
      (refusal) {
        if (refusal.kind == AdvisoryRefusalKind.unknown) {
          // Not "failed": wait for the chain to say.
          setState(() {
            _busy = false;
            _sent = true;
            _uncertain = true;
          });
          watchChain();
          return;
        }
        setState(() {
          _busy = false;
          _error = refusal.message;
        });
        // A refusal on the merits means the eligibility shown is stale.
        if (const {
          AdvisoryRefusalKind.alreadyVoted,
          AdvisoryRefusalKind.notEligible,
          AdvisoryRefusalKind.votingClosed,
        }.contains(refusal.kind)) {
          ref.invalidate(
            advisoryEligibilityProvider((widget.proposal.id, address)),
          );
        }
      },
      (_) {
        setState(() {
          _busy = false;
          _sent = true;
        });
        watchChain();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final voter = ref.watch(advisoryVoterProvider);
    return Card(
      key: const Key('advisory-vote-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: voter.when(
          loading: () => const _Loading(),
          error: (_, _) => const _Line(
            "This wallet type can't vote yet.",
            key: Key('advisory-vote-status'),
          ),
          data: (v) => _forVoter(v),
        ),
      ),
    );
  }

  Widget _forVoter(AdvisoryVoter v) {
    final address = v.address;
    if (address == null) {
      return const _Line(
        'Create or import a wallet in the app to vote.',
        key: Key('advisory-vote-status'),
      );
    }
    if (!v.canSign) {
      return const _Line(
        "This wallet type can't vote yet.",
        key: Key('advisory-vote-status'),
      );
    }
    final eligibility = ref.watch(
      advisoryEligibilityProvider((widget.proposal.id, address)),
    );
    final children = <Widget>[
      const Text(
        'Your vote',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
    ];
    final e = eligibility.value;
    if (_sent && e?.voted == null) {
      children.add(
        _uncertain
            ? const _Line(
                advisoryVoteUnknownNote,
                key: Key('advisory-vote-unknown'),
                color: AppColors.warning,
              )
            : const _Line(
                advisoryPendingNote,
                key: Key('advisory-vote-sent'),
                color: AppColors.success,
              ),
      );
    } else if (e == null) {
      children.add(
        eligibility.hasError
            ? Row(
                children: [
                  const Expanded(
                    child: _Line(
                      "Couldn't check whether this wallet can vote.",
                      key: Key('advisory-vote-status'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      advisoryEligibilityProvider((
                        widget.proposal.id,
                        address,
                      )),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              )
            : const _Loading(),
      );
    } else if (e.refusalFor(createdAtBlock: widget.proposal.createdAtBlock)
        case final refusal?) {
      children.add(
        _Line(refusal.message, key: const Key('advisory-vote-status')),
      );
    } else {
      children.addAll([
        Text(
          'Wallet ${shortAdvisoryAddress(address)} can vote. Your device '
          'unlock signs it; no recovery words needed.',
          key: const Key('advisory-vote-status'),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const Key('advisory-vote-for'),
                onPressed: _busy ? null : () => _vote(address, true),
                child: const Text('Vote For'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                key: const Key('advisory-vote-against'),
                onPressed: _busy ? null : () => _vote(address, false),
                child: const Text('Vote Against'),
              ),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ]);
    }
    if (_error != null) {
      children.addAll([
        const SizedBox(height: 12),
        _Line(
          _error!,
          key: const Key('advisory-vote-error'),
          color: AppColors.error,
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// "0xa307fb…aa0d".
String shortAdvisoryAddress(String a) =>
    a.length > 12 ? '${a.substring(0, 8)}…${a.substring(a.length - 4)}' : a;

/// What the person signs, said exactly: the proposal, the choice, the wallet
/// and the network. Pops true to go ahead.
class AdvisoryVoteConfirmSheet extends StatelessWidget {
  const AdvisoryVoteConfirmSheet({
    super.key,
    required this.proposal,
    required this.approve,
    required this.address,
  });

  final AdvisoryProposal proposal;
  final bool approve;
  final String address;

  @override
  Widget build(BuildContext context) {
    final choice = approve ? 'For' : 'Against';
    const label = TextStyle(color: AppColors.textSecondary, fontSize: 12);
    Widget row(String name, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: label),
          const SizedBox(height: 2),
          SelectableText(value, key: key, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
    final network = TransferSigningDomain.configured;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: const Key('advisory-vote-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sign this vote?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            row('Proposal', proposal.title, key: const Key('sheet-title')),
            row('Proposal id', proposal.id),
            row('Your vote', choice, key: const Key('sheet-choice')),
            row('Wallet', address, key: const Key('sheet-wallet')),
            row(
              'Network',
              'WRFCoin ${network.networkId} (chain ${network.chainId})',
            ),
            const Text(
              'Unlocking signs exactly this with the wallet key kept on this '
              'phone. Your recovery words are never needed. A vote is final '
              'and only recorded; nothing it says is carried out.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('sheet-confirm'),
              icon: const Icon(Icons.fingerprint),
              label: Text('Unlock and vote $choice'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('sheet-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(color: color ?? AppColors.textSecondary, fontSize: 14),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
