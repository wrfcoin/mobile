import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner decision on mobile#271 (Option A): server-initiated push is out of
/// testnet scope. The app must not start a token service that can never obtain
/// a token and would target a backend route that does not exist.
void main() {
  test('main.dart starts no FCM token service or push-token request', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, isNot(contains('FcmTokenService')));
    expect(source, isNot(contains('fcm_token_service')));
    expect(source, isNot(contains('push-token')));
  });
}
