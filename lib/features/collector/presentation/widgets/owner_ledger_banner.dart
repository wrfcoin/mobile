import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/station_owner_models.dart';
import '../../data/services/station_owner_service.dart';
import '../providers/station_owner_providers.dart';

/// Pending-recovery warning for the current owner. Heights are exact; the
/// calendar wait is an estimate and is labelled as one.
class RecoveryBanner extends StatelessWidget {
  const RecoveryBanner({
    super.key,
    required this.pending,
    required this.observedAtHeight,
  });

  final PendingRecovery pending;
  final int observedAtHeight;

  @override
  Widget build(BuildContext context) {
    final remaining = pending.executableAtHeight - (observedAtHeight + 1);
    final wait = approxRecoveryWait(blocksRemaining: remaining);
    final closed = remaining <= 0;
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.red),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Someone has asked to take over this station.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              closed
                  ? "If this wasn't you, act now. The window to cancel has "
                        'closed.'
                  : "If this wasn't you, cancel now. It completes at block "
                        '${pending.executableAtHeight} ($wait, estimate) if '
                        'you do nothing.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashboard banner: shows only what the ledger confirms. Loading shows
/// nothing; a failed read shows a neutral "Status unavailable" chip that makes
/// no claim about the station (never a reassuring "all clear").
class OwnerLedgerBanner extends ConsumerWidget {
  const OwnerLedgerBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ownerStationLedgerProvider);
    if (async.hasError && !async.hasValue) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: Icon(Icons.help_outline, size: 18),
          label: Text('Status unavailable'),
        ),
      );
    }
    final ledger = async.asData?.value;
    if (ledger == null) return const SizedBox.shrink();
    final pending = ledger.pendingRecovery;
    return Column(
      children: [
        if (pending != null)
          RecoveryBanner(
            pending: pending,
            observedAtHeight: ledger.observedAtHeight,
          ),
        if (ledger.frozen)
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'This station is frozen since block '
                '${ledger.frozenSinceHeight}. It earns nothing until it is '
                'unfrozen.',
              ),
            ),
          ),
      ],
    );
  }
}
