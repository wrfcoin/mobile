import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';

import '../../test_helpers/fakes.dart';

void main() {
  group('BiometricService', () {
    test(
      'reports support when either biometrics or device support is available',
      () async {
        final service = BiometricService(
          client: FakeLocalAuthClient(canCheck: false, deviceSupported: true),
        );

        expect(await service.canCheckBiometrics(), isTrue);
      },
    );

    test(
      'returns false when the local auth client throws during support check',
      () async {
        final service = BiometricService(
          client: FakeLocalAuthClient(throwOnCanCheck: true),
        );

        expect(await service.canCheckBiometrics(), isFalse);
      },
    );

    test('returns false when authentication throws', () async {
      final service = BiometricService(
        client: FakeLocalAuthClient(throwOnAuthenticate: true),
      );

      expect(await service.authenticate(reason: 'test'), isFalse);
    });

    test('returns empty list when biometric discovery throws', () async {
      final service = BiometricService(
        client: FakeLocalAuthClient(throwOnGetAvailable: true),
      );

      expect(await service.getAvailableBiometrics(), isEmpty);
    });

    test('passes through available biometrics', () async {
      final service = BiometricService(
        client: FakeLocalAuthClient(
          availableBiometrics: const [BiometricType.face],
        ),
      );

      expect(await service.getAvailableBiometrics(), [BiometricType.face]);
    });

    test(
      'one prompt offers biometrics and device credentials together',
      () async {
        final client = FakeLocalAuthClient(
          biometricOnlyAuthenticateResult: false,
          authenticateResult: true,
          availableBiometrics: const [BiometricType.face],
        );
        final service = BiometricService(client: client);

        expect(await service.authenticate(reason: 'test'), isTrue);
        expect(client.authenticateBiometricOnlyCalls, [false]);
      },
    );

    test(
      'a declined combined prompt ends the attempt without another prompt',
      () async {
        final client = FakeLocalAuthClient(authenticateResult: false);
        expect(await BiometricService(client: client).authenticate(), isFalse);
        expect(client.authenticateBiometricOnlyCalls, [false]);
      },
    );

    test('an unsupported device sends no authentication prompt', () async {
      final client = FakeLocalAuthClient(
        deviceSupported: false,
        canCheck: false,
      );
      expect(await BiometricService(client: client).authenticate(), isFalse);
      expect(client.authenticateBiometricOnlyCalls, isEmpty);
    });

    test('uses device credential when biometrics are unavailable', () async {
      final client = FakeLocalAuthClient(
        availableBiometrics: const [],
        deviceSupported: true,
        authenticateResult: true,
      );
      final service = BiometricService(client: client);

      expect(await service.authenticate(reason: 'test'), isTrue);
      expect(client.authenticateBiometricOnlyCalls, [false]);
    });
    // mobile#320: local_auth 3.x throws on a cancel. A cancel is the user's
    // answer, so it must not open a second (device-credential) prompt.
    for (final code in const [
      LocalAuthExceptionCode.userCanceled,
      LocalAuthExceptionCode.systemCanceled,
      LocalAuthExceptionCode.timeout,
      LocalAuthExceptionCode.authInProgress,
      LocalAuthExceptionCode.uiUnavailable,
    ]) {
      test(
        'a biometric prompt ending in ${code.name} is not re-prompted',
        () async {
          final client = _ThrowingLocalAuthClient(
            LocalAuthException(code: code),
          );
          final service = BiometricService(client: client);

          expect(await service.authenticate(reason: 'test'), isFalse);
          expect(client.prompts, 1);
        },
      );
    }

    test(
      'device credential remains available without a second biometric prompt',
      () async {
        final client = _ThrowingLocalAuthClient(
          const LocalAuthException(
            code: LocalAuthExceptionCode.biometricLockout,
          ),
          throwOnlyForBiometricOnly: true,
        );
        final service = BiometricService(client: client);

        expect(await service.authenticate(reason: 'test'), isTrue);
        expect(client.prompts, 1);
      },
    );
  });
}

class _ThrowingLocalAuthClient implements LocalAuthClient {
  _ThrowingLocalAuthClient(
    this.error, {
    this.throwOnlyForBiometricOnly = false,
  });

  final LocalAuthException error;
  final bool throwOnlyForBiometricOnly;
  int prompts = 0;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    prompts++;
    if (biometricOnly || !throwOnlyForBiometricOnly) throw error;
    return true;
  }

  @override
  Future<bool> canCheckBiometrics() async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [
    BiometricType.strong,
  ];
}
