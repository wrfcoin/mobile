import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/services/station_owner_service.dart';
import '../providers/station_owner_providers.dart';
import '../widgets/confirm_dialog.dart';

/// Claimant side of a recovery. The operator prepares and files the claim:
/// the phone only COUNTERSIGNS the operator's body (offline, text handed back
/// to the operator, nothing submitted) and, once the notice window has
/// passed, can complete the recovery with an unsigned transaction.
class StationRecoveryScreen extends ConsumerStatefulWidget {
  const StationRecoveryScreen({super.key});

  @override
  ConsumerState<StationRecoveryScreen> createState() => _State();
}

class _State extends ConsumerState<StationRecoveryScreen> {
  final _request = TextEditingController();
  final _stationId = TextEditingController();
  RecoveryAcceptFlow? _flow;
  String? _returnText;
  RecoveryExecuteSubmission? _execution;
  TransferStatus _status = TransferStatus.pendingConfirmation;
  String? _error;
  bool _working = false;

  @override
  void dispose() {
    _flow?.close();
    _request.dispose();
    _stationId.dispose();
    super.dispose();
  }

  Future<void> _review() async {
    if (_working) return;
    _flow?.close();
    setState(() {
      _flow = null;
      _returnText = null;
      _error = null;
      _working = true;
    });
    try {
      final flow = await ref
          .read(stationOwnerServiceProvider)
          .beginRecoveryAccept(_request.text);
      if (!mounted) {
        flow.close();
        return;
      }
      setState(() => _flow = flow);
    } catch (e) {
      if (mounted) setState(() => _error = stationOwnerErrorText(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _countersign() async {
    final flow = _flow;
    if (flow == null || _working) return;
    // In flight from the first tap: a second tap cannot open a second dialog
    // or countersign twice.
    setState(() => _working = true);
    try {
      final ok = await showConfirmDialog(
        context,
        title: 'Countersign this recovery?',
        body:
            'This lets the operator file a claim to move this station to '
            'your wallet. The current owner has about 14 days to cancel it. '
            'Nothing is sent from this phone.',
        yes: 'Countersign',
        destructive: false,
      );
      if (!mounted || ok != true) return;
      setState(() => _error = null);
      final text = await flow.countersign();
      flow.close();
      if (!mounted) return;
      setState(() {
        _returnText = text;
        _flow = null;
        _stationId.text = flow.request.body.stationId;
      });
    } catch (e) {
      if (mounted) setState(() => _error = stationOwnerErrorText(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _complete() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final sub = await ref
          .read(stationOwnerServiceProvider)
          .executeRecovery(_stationId.text.trim());
      if (!mounted) return;
      setState(() {
        _execution = sub;
        _status = TransferStatus.pendingConfirmation;
      });
    } catch (e) {
      if (mounted) setState(() => _error = stationOwnerErrorText(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _check() async {
    final sub = _execution;
    if (sub == null) return;
    final status = await ref
        .read(stationOwnerServiceProvider)
        .checkRecoveryExecuted(sub);
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Station recovery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_execution != null)
            _Pending(status: _status, onCheck: _check)
          else ...[
            const Text(
              'Paste the recovery request from the operator.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('recovery-field'),
              controller: _request,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Recovery request',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _working ? null : _review,
              child: const Text('Review recovery request'),
            ),
            if (_flow != null)
              _Review(flow: _flow!, onCountersign: _countersign),
            if (_returnText != null) _Return(text: _returnText!),
            const Divider(height: 32),
            const Text(
              'After the waiting period, complete the recovery.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('station-id-field'),
              controller: _stationId,
              decoration: const InputDecoration(
                labelText: 'Station id',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _working ? null : _complete,
              child: const Text('Complete recovery'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.flow, required this.onCountersign});
  final RecoveryAcceptFlow flow;
  final VoidCallback? onCountersign;

  @override
  Widget build(BuildContext context) {
    final b = flow.request.body;
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 12)),
          SelectableText(v),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Only countersign if you are the real owner who lost access and '
          'the operator asked you to. Check every line.',
        ),
        row('Station', b.stationId),
        row('From (current owner)', b.fromOwnerAddress),
        row('To (this wallet)', b.toOwnerAddress),
        row('Recovery number', '${b.recoveryNonce}'),
        row('Network', '${b.chainId} / ${b.networkId}'),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: onCountersign,
          child: const Text('Countersign'),
        ),
      ],
    );
  }
}

class _Return extends StatelessWidget {
  const _Return({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      const Text(
        'Give this back to the operator',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Center(
        child: QrImageView(
          data: text,
          size: 260,
          backgroundColor: Colors.white,
        ),
      ),
      SelectableText(text, style: const TextStyle(fontSize: 11)),
      TextButton(
        onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        child: const Text('Copy'),
      ),
      const Text(
        'The recovery is not filed until the operator files it. Nothing was '
        'sent from this phone.',
      ),
    ],
  );
}

class _Pending extends StatelessWidget {
  const _Pending({required this.status, required this.onCheck});
  final TransferStatus status;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    if (status == TransferStatus.confirmed) {
      return const Text(
        'Recovery complete. This station is now yours.',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pending confirmation',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'The network accepted your request, but it is not applied yet. '
          'Ownership changes only when the network ledger shows it.',
        ),
        if (status == TransferStatus.unknown) ...[
          const SizedBox(height: 8),
          const Text('Status unavailable right now. Try again.'),
        ],
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onCheck, child: const Text('Check again')),
      ],
    );
  }
}
