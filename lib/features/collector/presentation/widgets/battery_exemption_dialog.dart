import 'package:flutter/material.dart';

import '../providers/collector_provider.dart';

/// Asks once whether Android's battery limits may be lifted for collection.
/// Either answer is final: the app never asks again, and collection runs
/// either way. Nothing else in the app raises this.
Future<void> askBatteryExemptionOnce(
  BuildContext context,
  CollectorNotifier notifier,
) async {
  if (!await notifier.shouldAskBatteryExemption()) return;
  if (!context.mounted) return;
  final allow = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keep collecting while the phone sleeps?'),
      content: const Text(
        'To save battery, Android can pause or stop collection when the phone '
        'is idle. You can let WRFCoin ignore those limits. Readings are then '
        'steadier, and it uses more battery.\n\n'
        'Android asks you to confirm next. On a Samsung phone you may also '
        'need to set WRFCoin to Unrestricted in its battery settings.\n\n'
        'Collection stays on either way, and we will not ask again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No thanks'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  await notifier.answerBatteryExemption(allow: allow ?? false);
}
