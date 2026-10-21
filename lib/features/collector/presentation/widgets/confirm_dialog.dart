import 'package:flutter/material.dart';

/// A confirm dialog whose buttons answer at most ONCE. A second tap (or a
/// second programmatic call) on either button is ignored, so it can never pop
/// a second route (such as the screen underneath).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  Widget? content,
  required String yes,
  String no = 'Cancel',
  bool destructive = true,
}) async {
  var answered = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      void answer(bool value) {
        if (answered) return;
        answered = true;
        Navigator.pop(dialogContext, value);
      }

      return AlertDialog(
        title: Text(title),
        content: content ?? Text(body ?? ''),
        actions: [
          TextButton(onPressed: () => answer(false), child: Text(no)),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => answer(true),
            child: Text(yes),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
