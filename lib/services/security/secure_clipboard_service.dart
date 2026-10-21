import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final secureClipboardServiceProvider = Provider<SecureClipboardService>((ref) {
  return SecureClipboardService();
});

/// Copies a secret (the recovery phrase) as a sensitive clip and clears it
/// again only while the clip is still the one this app put there
/// (mobile#320). The Android side lives in MainActivity.kt.
///
/// The clip is matched by a random label, so clearing never reads the
/// secret back. Android hides the clipboard from an app without focus, so a
/// clear attempted in the background reports [ClearResult.unreadable] and the
/// caller tries again on resume.
class SecureClipboardService {
  static const _channel = MethodChannel(
    'com.wrfcoin.wrfcoin_mobile/secure_clipboard',
  );

  /// A fresh label for one copy. It carries no part of the secret.
  static String newLabel([Random? random]) {
    final r = random ?? Random.secure();
    final suffix = List.generate(
      8,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'wrfcoin-recovery-$suffix';
  }

  /// Copies [text] under [label] as a sensitive clip. Returns false when the
  /// platform has no secure clipboard; nothing is copied then.
  Future<bool> copySensitive({
    required String text,
    required String label,
  }) async {
    if (kIsWeb) return false;
    try {
      final ok = await _channel.invokeMethod<Object?>('copySensitive', {
        'text': text,
        'label': label,
      });
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Clears the clipboard if it still holds the clip copied under [label].
  Future<ClearResult> clearIfOurs(String label) async {
    if (kIsWeb) return ClearResult.done;
    try {
      final result = await _channel.invokeMethod<Object?>('clearIfOurs', {
        'label': label,
      });
      return result == 'unreadable' ? ClearResult.unreadable : ClearResult.done;
    } on MissingPluginException {
      return ClearResult.done;
    } on PlatformException {
      return ClearResult.unreadable;
    }
  }
}

enum ClearResult {
  /// Cleared, or the clipboard no longer holds our clip.
  done,

  /// The clipboard could not be inspected (app not focused); retry later.
  unreadable,
}
