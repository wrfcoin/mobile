import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/services/station_owner_exchange.dart';
import '../../data/services/station_owner_service.dart';
import '../providers/station_owner_providers.dart';
import '../widgets/confirm_dialog.dart';

/// New-owner side: show a receive code, verify an offer field by field, then
/// countersign and submit. A 201 is "pending confirmation"; ownership is
/// claimed only when the ledger shows it.
class StationAcceptScreen extends ConsumerStatefulWidget {
  const StationAcceptScreen({super.key});

  @override
  ConsumerState<StationAcceptScreen> createState() => _State();
}

class _State extends ConsumerState<StationAcceptScreen> {
  final _offer = TextEditingController();
  ReceiveCode? _myCode;
  AcceptFlow? _flow;
  TransferSubmission? _submission;
  TransferStatus _status = TransferStatus.pendingConfirmation;
  String? _error;
  bool _working = false;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    _flow?.close();
    _offer.dispose();
    super.dispose();
  }

  Future<void> _showMyCode() async {
    try {
      final code = await ref.read(stationOwnerServiceProvider).myReceiveCode();
      if (mounted) setState(() => _myCode = code);
    } catch (e) {
      if (mounted) setState(() => _error = stationOwnerErrorText(e));
    }
  }

  Future<void> _review() async {
    if (_working) return;
    _flow?.close();
    setState(() {
      _flow = null;
      _error = null;
      _working = true;
    });
    try {
      final flow = await ref
          .read(stationOwnerServiceProvider)
          .beginAccept(_offer.text);
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

  Future<void> _accept() async {
    final flow = _flow;
    if (flow == null || _working) return;
    // In flight from the first tap: a second tap cannot open a second dialog
    // or start a second accept.
    setState(() => _working = true);
    try {
      final ok = await showConfirmDialog(
        context,
        title: 'Take ownership of this station?',
        body:
            'You will own station ${flow.offer.body.stationId} and its '
            'earnings once the network confirms. Only accept from someone '
            'you trust.',
        yes: 'Accept station',
        destructive: false,
      );
      if (!mounted || ok != true) return;
      setState(() => _error = null);
      final sub = await flow.accept();
      flow.close();
      if (!mounted) return;
      setState(() {
        _submission = sub;
        _flow = null;
        _status = TransferStatus.pendingConfirmation;
      });
      _poll = Timer.periodic(const Duration(seconds: 10), (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _error = stationOwnerErrorText(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _check() async {
    final sub = _submission;
    if (sub == null) return;
    final status = await ref
        .read(stationOwnerServiceProvider)
        .checkTransferApplied(sub);
    if (!mounted) return;
    setState(() => _status = status);
    if (status == TransferStatus.confirmed) _poll?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final sub = _submission;
    return Scaffold(
      appBar: AppBar(title: const Text('Accept a station')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (sub != null)
            _Pending(status: _status, onCheck: _check)
          else ...[
            _Receive(code: _myCode, onShow: _showMyCode),
            const Divider(height: 32),
            const Text('Paste the transfer request from the sender.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('offer-field'),
              controller: _offer,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Transfer request',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _working ? null : _review,
              child: const Text('Review offer'),
            ),
            if (_flow != null)
              _Review(flow: _flow!, onAccept: _working ? null : _accept),
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

class _Receive extends StatelessWidget {
  const _Receive({required this.code, required this.onShow});
  final ReceiveCode? code;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final c = code;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your receive code',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Show this to the current owner. It contains only your public '
          'address and public key.',
        ),
        const SizedBox(height: 8),
        if (c == null)
          OutlinedButton(
            onPressed: onShow,
            child: const Text('Show my receive code'),
          )
        else ...[
          Center(
            child: QrImageView(
              data: c.encode(),
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text('Address: ${c.address}'),
          const SizedBox(height: 8),
          SelectableText(c.encode(), style: const TextStyle(fontSize: 11)),
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: c.encode())),
            child: const Text('Copy'),
          ),
        ],
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.flow, required this.onAccept});
  final AcceptFlow flow;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final b = flow.offer.body;
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
          "Check every line. The sender's signature is valid and the "
          'station is theirs to give.',
        ),
        row('Station', b.stationId),
        row('From (current owner)', b.fromOwnerAddress),
        row('To (this wallet)', b.toOwnerAddress),
        row('Valid until block', '${b.expiresAtHeight}'),
        row('Network', '${b.chainId} / ${b.networkId}'),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: onAccept,
          child: const Text('Accept station'),
        ),
      ],
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({required this.status, required this.onCheck});
  final TransferStatus status;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    if (status == TransferStatus.confirmed) {
      return const Text(
        'You now own this station.',
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
