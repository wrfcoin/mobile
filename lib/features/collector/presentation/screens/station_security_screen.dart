import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/crypto/station_signing.dart';
import '../../data/models/station_owner_models.dart';
import '../../data/services/station_owner_service.dart';
import '../providers/station_owner_providers.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/owner_ledger_banner.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
import 'station_submit_token_screen.dart';

/// Copy for each owner action: the confirm dialog and the text shown only
/// once the ledger confirms the change.
class _ActionCopy {
  const _ActionCopy({
    required this.button,
    required this.title,
    required this.body,
    required this.yes,
    required this.confirmed,
    required this.pendingNote,
  });
  final String button;
  final String title;
  final String body;
  final String yes;
  final String confirmed;
  final String pendingNote;
}

const Map<StationOwnerAction, _ActionCopy> _copy = {
  StationOwnerAction.reportStolen: _ActionCopy(
    button: 'Report stolen',
    title: 'Freeze this station?',
    body:
        'This stops it earning until you unfreeze it. Only do this if the '
        'device is lost or stolen.',
    yes: 'Freeze station',
    confirmed: 'Station frozen. It earns nothing until it is unfrozen.',
    pendingNote: 'The station is frozen only when the network ledger shows it.',
  ),
  StationOwnerAction.unfreeze: _ActionCopy(
    button: 'Unfreeze',
    title: 'Unfreeze this station?',
    body:
        'It will resume earning. Only unfreeze if the device is safe and back '
        'in your hands.',
    yes: 'Unfreeze station',
    confirmed: 'Station unfrozen. It can earn again.',
    pendingNote:
        'The station is unfrozen only when the network ledger shows it.',
  ),
  StationOwnerAction.deactivate: _ActionCopy(
    button: 'Deactivate',
    title: 'Deactivate this station?',
    body:
        'It stops earning until you reactivate it. You can reverse this '
        'later.',
    yes: 'Deactivate station',
    confirmed: 'Station deactivated. It earns nothing until you reactivate it.',
    pendingNote:
        'The station is deactivated only when the network ledger shows it.',
  ),
  StationOwnerAction.reactivate: _ActionCopy(
    button: 'Reactivate',
    title: 'Reactivate this station?',
    body: 'It will resume earning.',
    yes: 'Reactivate station',
    confirmed: 'Station reactivated. It can earn again.',
    pendingNote:
        'The station is reactivated only when the network ledger shows it.',
  ),
};

const _cancelCopy = _ActionCopy(
  button: 'Cancel recovery',
  title: 'Cancel this recovery?',
  body: '',
  yes: 'Cancel recovery',
  confirmed: 'Recovery cancelled. This station is still yours.',
  pendingNote:
      'The recovery is cancelled only when the network ledger shows it.',
);

/// Owner actions for this wallet's own station. Nothing claims success from
/// a submit: only the ledger can confirm the change.
class StationSecurityScreen extends ConsumerStatefulWidget {
  const StationSecurityScreen({super.key});

  @override
  ConsumerState<StationSecurityScreen> createState() => _State();
}

class _State extends ConsumerState<StationSecurityScreen> {
  Future<TransferStatus> Function()? _checker;
  _ActionCopy? _doing;
  TransferStatus _status = TransferStatus.pendingConfirmation;
  String? _error;
  bool _working = false;

  Future<void> _act(StationOwnerAction action) async {
    if (_working) return;
    final copy = _copy[action]!;
    // In flight from the first tap (see the dialog below).
    setState(() => _working = true);
    try {
      final ok = await showConfirmDialog(
        context,
        title: copy.title,
        body: copy.body,
        yes: copy.yes,
      );
      if (!mounted || ok != true) return;
      setState(() => _error = null);
      final svc = ref.read(stationOwnerServiceProvider);
      final sub = await svc.performOwnerAction(action);
      if (!mounted) return;
      setState(() {
        _checker = () => svc.checkActionApplied(sub);
        _doing = copy;
        _status = TransferStatus.pendingConfirmation;
      });
    } catch (e) {
      if (mounted) setState(() => _error = stationOwnerErrorText(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancelRecovery() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final ok = await showConfirmDialog(
        context,
        title: 'Cancel this recovery?',
        body:
            'Do this if you did NOT start it. The person asking to take over '
            'this station will be refused. You must still hold this wallet.',
        yes: 'Cancel recovery',
        no: 'Not now',
      );
      if (!mounted || ok != true) return;
      setState(() => _error = null);
      final svc = ref.read(stationOwnerServiceProvider);
      final sub = await svc.cancelRecovery();
      if (!mounted) return;
      setState(() {
        _checker = () => svc.checkRecoveryCancelled(sub);
        _doing = _cancelCopy;
        _status = TransferStatus.pendingConfirmation;
      });
    } catch (e) {
      if (mounted) setState(() => _error = stationOwnerErrorText(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _check() async {
    final checker = _checker;
    if (checker == null) return;
    final status = await checker();
    if (!mounted) return;
    setState(() => _status = status);
    if (status == TransferStatus.confirmed) {
      ref.invalidate(ownerStationLedgerProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ownerStationLedgerProvider);
    final doing = _doing;
    return Scaffold(
      appBar: AppBar(title: const Text('Station security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton(
            onPressed: _working
                ? null
                : () async {
                    try {
                      final address = (await ref.read(walletProvider.future))
                          ?.address;
                      if (address == null) {
                        throw StateError('Wallet unavailable.');
                      }
                      final stationId = deriveMobileStationId(
                        address.trim().toLowerCase(),
                      );
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              StationSubmitTokenScreen(stationId: stationId),
                        ),
                      );
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _error = 'This phone station is unavailable.',
                        );
                      }
                    }
                  },
            child: const Text('Station submit credential'),
          ),
          if (_checker != null && doing != null)
            _Pending(status: _status, copy: doing, onCheck: _check)
          else
            ledger.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Station status is unavailable right now. Nothing was '
                    'changed.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(ownerStationLedgerProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              data: (l) => _Status(
                ledger: l,
                working: _working,
                onAct: _act,
                onCancelRecovery: _cancelRecovery,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.ledger,
    required this.working,
    required this.onAct,
    required this.onCancelRecovery,
  });

  final OwnerLedger ledger;
  final bool working;
  final void Function(StationOwnerAction) onAct;
  final VoidCallback onCancelRecovery;

  @override
  Widget build(BuildContext context) {
    final pending = ledger.pendingRecovery;
    final cancellable =
        pending != null &&
        ledger.consentActive &&
        ledger.observedAtHeight + 1 < pending.executableAtHeight;
    final headline = ledger.frozen
        ? 'Frozen since block ${ledger.frozenSinceHeight}. It earns nothing '
              'until it is unfrozen.'
        : ledger.ownerDeactivated
        ? 'This station is deactivated.'
        : pending != null
        ? 'A recovery is pending for this station.'
        : 'Your station is active.';
    // Consensus: freeze/deactivate/reactivate refuse a frozen station, and
    // unfreeze needs one; deactivate/reactivate toggle owner_deactivated.
    final actions = <StationOwnerAction>[
      if (ledger.frozen) StationOwnerAction.unfreeze,
      if (!ledger.frozen) StationOwnerAction.reportStolen,
      if (!ledger.frozen && ledger.ownerDeactivated)
        StationOwnerAction.reactivate,
      if (!ledger.frozen && !ledger.ownerDeactivated)
        StationOwnerAction.deactivate,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pending != null)
          RecoveryBanner(
            pending: pending,
            observedAtHeight: ledger.observedAtHeight,
          ),
        Text(
          headline,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (cancellable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.red,
              ),
              onPressed: working ? null : onCancelRecovery,
              child: const Text('Cancel recovery'),
            ),
          ),
        if (!ledger.actionsActive)
          const Text('Theft protection is not active on the network yet.')
        else
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ElevatedButton(
                style: a == StationOwnerAction.reportStolen
                    ? ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.red,
                      )
                    : null,
                onPressed: working ? null : () => onAct(a),
                child: Text(_copy[a]!.button),
              ),
            ),
      ],
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({
    required this.status,
    required this.copy,
    required this.onCheck,
  });
  final TransferStatus status;
  final _ActionCopy copy;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    if (status == TransferStatus.confirmed) {
      return Text(
        copy.confirmed,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
        Text(
          'The network accepted your request, but it is not applied yet. '
          '${copy.pendingNote}',
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
