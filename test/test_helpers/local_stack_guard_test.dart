import 'package:flutter_test/flutter_test.dart';

import 'local_stack_guard.dart';

void main() {
  group('nonLoopbackReason', () {
    for (final url in [
      'http://127.0.0.1:18080/api',
      'http://localhost:18577',
      'https://LOCALHOST/api',
      'http://[::1]:18577',
    ]) {
      test('accepts $url', () {
        expect(nonLoopbackReason('URL', url), isNull);
      });
    }

    for (final url in [
      'https://testnet.wrfcoin.example/api',
      'http://192.0.2.10:8556',
      'http://100.64.1.2:8556',
      'http://0.0.0.0:18577',
      'http://node.local:8556',
      'http://127.0.0.1.nip.io:8556',
      'http://127.0.0.1@testnet.wrfcoin.example/api',
      'http://user@127.0.0.1:18577',
      'ftp://127.0.0.1/api',
      '127.0.0.1:18577',
      '',
    ]) {
      test('refuses "$url"', () {
        expect(nonLoopbackReason('URL', url), isNotNull);
      });
    }

    test('names the variable in the reason', () {
      expect(
        nonLoopbackReason('WRFCOIN_E2E_CORE4_URL', 'http://192.0.2.10:8556'),
        contains('WRFCOIN_E2E_CORE4_URL'),
      );
    });
  });
}
