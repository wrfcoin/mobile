import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/security/screen_security_service.dart';

import '../../test_helpers/fakes.dart';

void main() {
  group('ScreenSecurityService', () {
    late FakeScreenSecurityClient client;
    late ScreenSecurityService service;

    setUp(() {
      client = FakeScreenSecurityClient();
      service = ScreenSecurityService(client: client);
    });

    test('enableProtection delegates to client', () async {
      await service.enableProtection();

      expect(client.enableCalls, 1);
      expect(client.protectionEnabled, isTrue);
    });

    test('disableProtection delegates to client', () async {
      await service.enableProtection();
      await service.disableProtection();

      expect(client.disableCalls, 1);
      expect(client.protectionEnabled, isFalse);
    });

    test('enableProtection swallows client exceptions', () async {
      final throwingService = ScreenSecurityService(
        client: _ThrowingScreenSecurityClient(),
      );

      // Should not throw
      await throwingService.enableProtection();
    });

    test('disableProtection swallows client exceptions', () async {
      final throwingService = ScreenSecurityService(
        client: _ThrowingScreenSecurityClient(),
      );

      // Should not throw
      await throwingService.disableProtection();
    });
  });
}

class _ThrowingScreenSecurityClient implements ScreenSecurityClient {
  @override
  Future<void> enableProtection() async {
    throw Exception('platform error');
  }

  @override
  Future<void> disableProtection() async {
    throw Exception('platform error');
  }
}
