import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../test_helpers/fakes.dart';

void main() {
  group('KeyManager', () {
    late InMemoryKeyValueStorage storage;

    setUp(() {
      storage = InMemoryKeyValueStorage();
    });

    test('stores keys and reports wallet presence', () async {
      final manager = KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: storage,
      );

      await manager.storeKeys(
        mnemonic: 'seed phrase',
        privateKey: '0xabc',
        address: 'wrf1testwallet0000000000',
      );

      expect(await manager.hasWallet(), isTrue);
      expect(await manager.getAddress(), 'wrf1testwallet0000000000');
      expect(await manager.getKeyScheme(), KeyManager.canonicalKeyScheme);
      expect(await manager.canSignTransactions(), isTrue);
    });

    test(
      'an existing install without a scheme marker remains legacy receive-only',
      () async {
        await storage.write(key: 'wrf_address', value: 'wrf1legacy');
        final manager = KeyManager(
          biometric: BiometricService(client: FakeLocalAuthClient()),
          storage: storage,
        );

        expect(await manager.getAddress(), 'wrf1legacy');
        expect(await manager.getKeyScheme(), KeyManager.legacyKeyScheme);
        expect(await manager.canSignTransactions(), isFalse);
      },
    );

    test('returns private key after successful biometric auth', () async {
      final manager = KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(authenticateResult: true),
        ),
        storage: storage,
      );
      await manager.storeKeys(
        mnemonic: 'seed phrase',
        privateKey: '0xabc',
        address: 'wrf1testwallet0000000000',
      );

      expect(await manager.getPrivateKey(), '0xabc');
    });

    test(
      'stores a separate login key and address for canonical wallets',
      () async {
        final manager = KeyManager(
          biometric: BiometricService(
            client: FakeLocalAuthClient(authenticateResult: true),
          ),
          storage: storage,
        );
        await manager.storeKeys(
          mnemonic: 'seed phrase',
          privateKey: '0xed25519',
          address: '0xchain',
          loginPrivateKey: '0xsecp256k1',
          loginAddress: '0xlogin',
        );

        expect(await manager.getAddress(), '0xchain');
        expect(await manager.getLoginAddress(), '0xlogin');
        expect(await manager.getLoginPrivateKey(), '0xsecp256k1');
      },
    );

    test('returns null when biometric authentication fails', () async {
      final manager = KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(
            authenticateResult: false,
            biometricOnlyAuthenticateResult: false,
          ),
        ),
        storage: storage,
      );
      await manager.storeKeys(
        mnemonic: 'seed phrase',
        privateKey: '0xabc',
        address: 'wrf1testwallet0000000000',
      );

      expect(await manager.getPrivateKey(), isNull);
    });

    test('allows key access via device credential fallback', () async {
      final manager = KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(
            availableBiometrics: const [BiometricType.face],
            biometricOnlyAuthenticateResult: false,
            authenticateResult: true,
          ),
        ),
        storage: storage,
      );
      await manager.storeKeys(
        mnemonic: 'seed phrase',
        privateKey: '0xabc',
        address: 'wrf1testwallet0000000000',
      );

      expect(await manager.getPrivateKey(), '0xabc');
    });

    test('masks long addresses for display', () {
      expect(KeyManager.maskAddress('wrf1234567890abcdef'), 'wrf123...cdef');
    });

    test('leaves short addresses unchanged', () {
      expect(KeyManager.maskAddress('wrf1234'), 'wrf1234');
    });

    test(
      'getMnemonic returns mnemonic after successful biometric auth',
      () async {
        final manager = KeyManager(
          biometric: BiometricService(
            client: FakeLocalAuthClient(authenticateResult: true),
          ),
          storage: storage,
        );
        await manager.storeKeys(
          mnemonic: 'seed phrase',
          privateKey: '0xabc',
          address: 'wrf1testwallet0000000000',
        );

        expect(await manager.getMnemonic(), 'seed phrase');
      },
    );

    test('getMnemonic returns null when biometric auth fails', () async {
      final manager = KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(authenticateResult: false),
        ),
        storage: storage,
      );
      await manager.storeKeys(
        mnemonic: 'seed phrase',
        privateKey: '0xabc',
        address: 'wrf1testwallet0000000000',
      );

      expect(await manager.getMnemonic(), isNull);
    });

    test('lockout activates after 5 failed auth attempts', () async {
      final manager = KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(authenticateResult: false),
        ),
        storage: storage,
      );
      await manager.storeKeys(
        mnemonic: 'seed phrase',
        privateKey: '0xabc',
        address: 'wrf1testwallet0000000000',
      );

      for (var i = 0; i < 5; i++) {
        await manager.getPrivateKey();
      }

      expect(manager.isLockedOut, isTrue);
    });

    test('locked-out user cannot access private key', () async {
      final manager = KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(authenticateResult: false),
        ),
        storage: storage,
      );
      await manager.storeKeys(
        mnemonic: 'seed phrase',
        privateKey: '0xabc',
        address: 'wrf1testwallet0000000000',
      );

      // Trigger lockout
      for (var i = 0; i < 5; i++) {
        await manager.getPrivateKey();
      }
      expect(manager.isLockedOut, isTrue);

      // Even with biometric succeeding, lockout blocks access
      expect(await manager.getPrivateKey(), isNull);
    });

    test('successful auth resets failure counter', () async {
      final authClient = _MutableAuthClient(false);
      final manager = KeyManager(
        biometric: BiometricService(client: authClient),
        storage: storage,
      );
      await manager.storeKeys(
        mnemonic: 'seed phrase',
        privateKey: '0xabc',
        address: 'wrf1testwallet0000000000',
      );

      // Fail 4 times
      for (var i = 0; i < 4; i++) {
        await manager.getPrivateKey();
      }
      expect(manager.isLockedOut, isFalse);

      // Succeed once — resets counter
      authClient.authenticateResult = true;
      expect(await manager.getPrivateKey(), '0xabc');

      // Fail 4 more times — should still NOT be locked out
      authClient.authenticateResult = false;
      for (var i = 0; i < 4; i++) {
        await manager.getPrivateKey();
      }
      expect(manager.isLockedOut, isFalse);
    });

    test('storeAuthSession and getAuthToken roundtrip', () async {
      final manager = KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: storage,
      );

      await manager.storeAuthSession(
        jwt: 'test-jwt-token',
        refreshToken: 'test-refresh',
        expiresInSeconds: 3600,
      );

      expect(await manager.getAuthToken(), 'test-jwt-token');
      expect(await manager.getRefreshToken(), 'test-refresh');
    });

    test('getAuthToken returns null for expired token', () async {
      final manager = KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: storage,
      );

      await manager.storeAuthSession(jwt: 'expired-jwt', expiresInSeconds: 0);

      // 30s-early-expiry check triggers immediately for a 0s token
      expect(await manager.getAuthToken(), isNull);
    });

    test('clearAuthSession removes all session keys', () async {
      final manager = KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: storage,
      );

      await manager.storeAuthSession(
        jwt: 'test-jwt',
        refreshToken: 'test-refresh',
        expiresInSeconds: 3600,
      );

      await manager.clearAuthSession();

      expect(await manager.getAuthToken(), isNull);
      expect(await manager.getRefreshToken(), isNull);
    });
  });
}

class _MutableAuthClient implements LocalAuthClient {
  bool authenticateResult;
  _MutableAuthClient(this.authenticateResult);

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async => authenticateResult;

  @override
  Future<bool> canCheckBiometrics() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => [];

  @override
  Future<bool> isDeviceSupported() async => true;
}
