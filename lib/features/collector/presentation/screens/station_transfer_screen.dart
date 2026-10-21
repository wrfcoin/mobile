import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/services/station_owner_exchange.dart';
import '../../data/services/station_owner_service.dart';
import '../providers/station_owner_providers.dart';
import '../widgets/confirm_dialog.dart';

/// Sender side of a station transfer. Signs one offer for the new owner; the
/// new owner accepts and submits. Nothing here claims the transfer is done:
/// only the ledger can confirm it.
class StationTransferScreen extends ConsumerStatefulWidget {
  const StationTransferScreen({super.key});

  @override
  ConsumerState<StationTransferScreen> createState() => _State();
}

class _State extends ConsumerState<StationTransferScreen> {
  final _code = TextEditingController();
  String? _error;
  bool _working = false;
  TransferStarted? _started;
  TransferStatus? _status;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _review() async {
    if (_working) return;
    final ReceiveCode to;
    try {
      to = ReceiveCode.decode(_code.text);
    } on FormatException {
      setState(() => _error = 'That is not a valid receive code.');
      return;
    }
    // In flight from the first tap: no second dialog, no second signing.
    setState(() {
      _error = null;
      _working = true;
    });
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Give this station away?',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'After they accept, you lose control of this station and its '
              'earnings. Check the full address below. A wrong address '
              'cannot be undone.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              to.address,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        yes: 'Sign transfer',
      );
      if (!mounted || confirmed != true) return;
      final started = await ref
          .read(stationOwnerServiceProvider)
          .startTransfer(to);
      if (!mounted) return;
      setState(() {
        _started = started;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = stationOwnerErrorText(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _checkStatus() async {
    final started = _started;
    if (started == null) return;
    final status = await ref
        .read(stationOwnerServiceProvider)
        .checkApplied(
          stationId: started.offer.body.stationId,
          toOwnerAddress: started.offer.body.toOwnerAddress,
          baselineNonce: started.offer.body.transferNonce,
        );
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final started = _started;
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer station')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (started == null) ...[
            const Text(
              'Ask the new owner to open "Accept a station" and show you '
              'their receive code, then paste it here.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('receive-code-field'),
              controller: _code,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: "New owner's receive code",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _working ? null : _review,
              child: const Text('Review transfer'),
            ),
          ] else
            _Offer(started: started, status: _status, onCheck: _checkStatus),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}

class _Offer extends StatelessWidget {
  const _Offer({
    required this.started,
    required this.status,
    required this.onCheck,
  });

  final TransferStarted started;
  final TransferStatus? status;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final text = started.offer.encode();
    final statusText = switch (status) {
      TransferStatus.confirmed =>
        'Transfer confirmed. This station now belongs to the new owner.',
      TransferStatus.pendingConfirmation =>
        'Waiting for the new owner to accept and the network to confirm.',
      TransferStatus.unknown => 'Status unavailable right now. Try again.',
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Show this to the new owner',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Center(
          child: QrImageView(
            data: text,
            size: 260,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text('Valid until block ${started.offer.body.expiresAtHeight}.'),
        const SizedBox(height: 8),
        SelectableText(text, style: const TextStyle(fontSize: 11)),
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
          child: const Text('Copy'),
        ),
        const SizedBox(height: 8),
        const Text(
          'The transfer is not complete until the new owner accepts and the '
          'network confirms it.',
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onCheck, child: const Text('Check status')),
        if (statusText != null) ...[
          const SizedBox(height: 8),
          Text(statusText),
        ],
      ],
    );
  }
}
