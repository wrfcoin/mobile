import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/crypto/advisory_action_signing.dart';
import '../../../../services/crypto/transfer_signing_domain.dart';
import '../../data/models/advisory_vote.dart';
import '../../data/repositories/governance_repository_impl.dart';
import '../providers/proposals_provider.dart';

/// The website's deposit note (frontend AdvisoryActions `DEPOSIT_NOTE`).
const String advisoryProposeDepositNote =
    'Proposing holds 1 WRF from this wallet. It comes back when the vote is '
    'decided, and stays held if fewer than 3 wallets vote.';

/// Shown after the relay takes a proposal.
const String advisoryProposeSentNote =
    'Sent. It appears once it is in a block (blocks come about every 77 '
    'seconds).';

/// A new advisory proposal: a title and a short text, signed with the app's
/// own wallet key after a confirm sheet and the device unlock. Same message,
/// rules and relay as the website's propose form.
class AdvisoryProposeScreen extends ConsumerStatefulWidget {
  const AdvisoryProposeScreen({super.key});

  @override
  ConsumerState<AdvisoryProposeScreen> createState() =>
      _AdvisoryProposeScreenState();
}

class _AdvisoryProposeScreenState extends ConsumerState<AdvisoryProposeScreen> {
  final _title = TextEditingController();
  final _summary = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The last refusal was an unknown outcome, not a failure.
  bool _uncertain = false;
  AdvisorySubmitted? _sent;

  @override
  void initState() {
    super.initState();
    void redraw() => setState(() {});
    _title.addListener(redraw);
    _summary.addListener(redraw);
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    super.dispose();
  }

  String? get _problem {
    if (_title.text.isEmpty && _summary.text.isEmpty) return null;
    return advisoryTextProblem(AdvisoryTextField.title, _title.text) ??
        advisoryTextProblem(AdvisoryTextField.summary, _summary.text);
  }

  Future<void> _review(String address) async {
    final title = _title.text;
    final summary = _summary.text;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AdvisoryProposeConfirmSheet(
        title: title,
        summary: summary,
        address: address,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(governanceRepositoryProvider)
        .proposeAdvisory(title: title, summary: summary);
    if (!mounted) return;
    result.match(
      (refusal) => setState(() {
        _busy = false;
        _error = refusal.message;
        _uncertain = refusal.kind == AdvisoryRefusalKind.unknown;
      }),
      (sent) {
        setState(() {
          _busy = false;
          _sent = sent;
        });
        ref.invalidate(advisoryProposalsProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final voter = ref.watch(advisoryVoterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New proposal')),
      body: voter.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const _Notice("This wallet type can't propose yet."),
        data: (v) {
          final address = v.address;
          if (address == null) {
            return const _Notice(
              'Create or import a wallet in the app to propose.',
            );
          }
          if (!v.canSign) {
            return const _Notice("This wallet type can't propose yet.");
          }
          final sent = _sent;
          if (sent != null) return _sentView(sent);
          return _form(address);
        },
      ),
    );
  }

  Widget _sentView(AdvisorySubmitted sent) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        advisoryProposeSentNote,
        key: Key('advisory-propose-sent'),
        style: TextStyle(color: AppColors.success, fontSize: 16),
      ),
      if (sent.proposalId != null) ...[
        const SizedBox(height: 8),
        Text(
          'Proposal ${sent.proposalId}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Back to proposals'),
      ),
    ],
  );

  Widget _form(String address) {
    final titleBytes = utf8.encode(_title.text).length;
    final summaryBytes = utf8.encode(_summary.text).length;
    final problem = _problem;
    final ready =
        !_busy &&
        _title.text.isNotEmpty &&
        _summary.text.isNotEmpty &&
        problem == null;
    const muted = TextStyle(color: AppColors.textSecondary, fontSize: 13);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'A title and a short text. Wallets vote for or against for about '
          '24 hours. Nothing it says is carried out.',
          style: muted,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('advisory-title'),
          controller: _title,
          enabled: !_busy,
          maxLines: 1,
          // One line: a pasted newline becomes a space (as the website).
          onChanged: (t) {
            if (t.contains('\n')) {
              _title.value = TextEditingValue(
                text: t.replaceAll('\n', ' '),
                selection: TextSelection.collapsed(offset: t.length),
              );
            }
          },
          decoration: InputDecoration(
            labelText: 'Title',
            helperText: '$titleBytes / $advisoryMaxTitleBytes bytes, one line',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('advisory-summary'),
          controller: _summary,
          enabled: !_busy,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: 'Text',
            helperText: '$summaryBytes / $advisoryMaxSummaryBytes bytes',
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          advisoryProposeDepositNote,
          key: Key('advisory-deposit-note'),
          style: muted,
        ),
        if (problem != null) ...[
          const SizedBox(height: 12),
          Text(
            problem,
            key: const Key('advisory-text-problem'),
            style: const TextStyle(color: AppColors.warning),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const Key('advisory-propose-error'),
            style: TextStyle(
              color: _uncertain ? AppColors.warning : AppColors.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('advisory-propose-review'),
          onPressed: ready ? () => _review(address) : null,
          child: const Text('Review and propose'),
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}

/// What the person signs, said exactly, with the deposit stated plainly.
/// Pops true to go ahead.
class AdvisoryProposeConfirmSheet extends StatelessWidget {
  const AdvisoryProposeConfirmSheet({
    super.key,
    required this.title,
    required this.summary,
    required this.address,
  });

  final String title;
  final String summary;
  final String address;

  @override
  Widget build(BuildContext context) {
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
          key: const Key('advisory-propose-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sign this proposal?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            row('Title', title, key: const Key('sheet-title')),
            row('Text', summary, key: const Key('sheet-summary')),
            row('Wallet', address, key: const Key('sheet-wallet')),
            row(
              'Network',
              'WRFCoin ${network.networkId} (chain ${network.chainId})',
            ),
            const Text(
              advisoryProposeDepositNote,
              key: Key('sheet-deposit'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Unlocking signs exactly this with the wallet key kept on this '
              'phone. Your recovery words are never needed. Nothing a '
              'proposal says is carried out.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('sheet-confirm'),
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock and propose'),
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

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        key: const Key('advisory-propose-status'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    ),
  );
}
