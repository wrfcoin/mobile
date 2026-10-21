// mobile#320: local_auth shows its prompt only from a FragmentActivity. With a
// plain FlutterActivity every biometric check fails with uiUnavailable before
// any prompt appears, so the wallet key could never be unlocked on Android
// (no login, no mnemonic reveal, no send). A Dart test cannot load the
// activity, so this pins the source.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'android/app/src/main/kotlin/com/wrfcoin/wrfcoin_mobile/MainActivity.kt',
  ).readAsStringSync();

  test('MainActivity is a FlutterFragmentActivity', () {
    expect(
      RegExp(r'class\s+MainActivity\s*:\s*FlutterFragmentActivity\s*\(')
          .hasMatch(source),
      isTrue,
    );
    expect(
      source.contains('import io.flutter.embedding.android.FlutterActivity\n'),
      isFalse,
    );
  });

  test('the secure clipboard channel marks the clip sensitive', () {
    expect(
      source.contains('"com.wrfcoin.wrfcoin_mobile/secure_clipboard"'),
      isTrue,
    );
    expect(source.contains('EXTRA_IS_SENSITIVE'), isTrue);
    expect(source.contains('"copySensitive"'), isTrue);
    expect(source.contains('"clearIfOurs"'), isTrue);
  });

  // local_auth's biometric prompt needs a Theme.AppCompat parent on Android
  // 8 and below (minSdk is 24). Flutter switches from LaunchTheme to
  // NormalTheme after launch, so both styles matter, in both modes.
  for (final dir in const ['values', 'values-night']) {
    test('$dir: LaunchTheme and NormalTheme have Theme.AppCompat parents', () {
      final styles = File('android/app/src/main/res/$dir/styles.xml')
          .readAsStringSync();
      for (final name in const ['LaunchTheme', 'NormalTheme']) {
        final parent = RegExp('<style name="$name" parent="([^"]+)"')
            .firstMatch(styles)
            ?.group(1);
        expect(parent, startsWith('Theme.AppCompat.'), reason: name);
      }
    });
  }
}
