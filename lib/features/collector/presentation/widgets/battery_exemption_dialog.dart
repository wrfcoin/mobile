import 'package:flutter/material.dart';

import '../../data/services/collector_preferences.dart';
import '../providers/collector_provider.dart';

/// What turning collection on does, before it does it. Returns false if the
/// user would rather not. Shown until accepted once.
Future<bool> explainBackgroundCollectionOnce(
  BuildContext context,
  CollectorPreferences preferences,
) async {
  if (await preferences.backgroundCollectionExplained()) return true;
  if (!context.mounted) return false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Collect with the app closed?'),
      content: const Text(
        'WRFCoin takes a weather reading about every 15 minutes and uploads '
        'it, even with the app closed.\n\n'
        'It uses your rough location, about 11 km. Only that rough area is '
        'stored or sent with your readings, never your exact position.\n\n'
        'A small permanent notification shows while this runs, with a Stop '
        'button. It uses more battery.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
  if (accepted != true) return false;
  await preferences.markBackgroundCollectionExplained();
  return true;
}

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
