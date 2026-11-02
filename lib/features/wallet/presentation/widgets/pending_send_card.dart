import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/wrf_units.dart';
import '../../data/models/pending_send.dart';
import '../providers/pending_send_provider.dart';

String _short(String address) => address.length <= 16
    ? address
    : '${address.substring(0, 8)}…${address.substring(address.length - 6)}';

/// The latest send, in the chain's words. Only "Send confirmed" says confirmed,
/// and only the provider's [PendingSendPhase.included] leads to it.
class PendingSendCard extends ConsumerWidget {
  const PendingSendCard({super.key, this.onSendScreen = false});

  /// On Send the row also explains why the button is off, and leaves out an
  /// outcome that has nothing to do with sending again.
  final bool onSendScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingSendProvider);
    final send = pending.send;
    if (send == null) return const SizedBox.shrink();
    if (onSendScreen && send.phase == PendingSendPhase.included) {
      return const SizedBox.shrink();
    }

    final amount = wrfBaseUnitsToDisplay(send.amountBaseUnits);
    final what = '${amount ?? send.amountBaseUnits} WRF to ${_short(send.to)}';
    final notifier = ref.read(pendingSendProvider.notifier);
    final (:title, :body, :icon, :color) = switch (send.phase) {
      PendingSendPhase.included => (
        title: 'Send confirmed',
        body: '$what is on chain in block ${send.blockHeight}.',
        icon: Icons.check_circle_outline,
        color: AppColors.success,
      ),
      PendingSendPhase.nonceUsedUnmatched => (
        title: 'Check this send',
        body:
            'The chain has applied a transaction with the number this send of '
            '$what used, but it could not be matched to this exact send. Check '
            'Recent Transactions and your balance.',
        icon: Icons.help_outline,
        color: AppColors.warning,
      ),
      _ when pending.overdue => (
        title: 'No confirmation yet',
        body:
            'The chain has not included this send of $what after '
            '${pendingSendTimeLimit.inMinutes} minutes. It may still go through, '
            'or it may have been dropped. Check your balance and Recent '
            'Transactions before sending the same amount again.',
        icon: Icons.schedule,
        color: AppColors.warning,
      ),
      PendingSendPhase.outcomeUnknown => (
        title: 'Send status unknown',
        body:
            'The network gave no clear answer to this send of $what, so it may '
            'or may not have gone through. Waiting for the chain to show which.',
        icon: Icons.help_outline,
        color: AppColors.warning,
      ),
      _ => (
        title: 'Transaction pending',
        body:
            'Sending $what. Waiting to be included in a block; one comes about '
            'every 77 seconds.',
        icon: Icons.hourglass_top,
        color: AppColors.warning,
      ),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('pending-send-card'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(body),
                  if (onSendScreen && pending.blocksSend) ...[
                    const SizedBox(height: 8),
                    const Text(
                      "You can't send again until it confirms.",
                      key: Key('pending-send-blocks-send'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (pending.checkFailed) ...[
                    const SizedBox(height: 8),
                    const Text(
                      "Can't read this send's status right now, so it may "
                      'already have changed. Tap Check now to try again.',
                      key: Key('pending-send-check-failed'),
                    ),
                  ],
                  Wrap(
                    spacing: 8,
                    children: [
                      if (send.phase != PendingSendPhase.included)
                        TextButton(
                          key: const Key('pending-send-check-now'),
                          onPressed: pending.checking ? null : notifier.check,
                          child: Text(
                            pending.checking ? 'Checking…' : 'Check now',
                          ),
                        ),
                      if (!pending.blocksSend)
                        TextButton(
                          key: const Key('pending-send-dismiss'),
                          onPressed: notifier.dismiss,
                          child: const Text('Dismiss'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
