import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../test_helpers/fakes.dart';

/// Fails the write of one slot, as a secure-storage error would. With
/// [failClearsAfterFailure] every later clear fails too (a store that broke
/// for good), so the rollback itself cannot finish.
class _FailingWriteStorage extends InMemoryKeyValueStorage {
  _FailingWriteStorage(
    this.failKey, {
    this.failClears = false,
    this.failClearsAfterFailure = false,
    this.failAllAfterFailure = false,
    this.failOnce = false,
  });
  final String failKey;
  final bool failClears;
  final bool failClearsAfterFailure;
  final bool failAllAfterFailure;
  final bool failOnce;
  var _failed = false;
  final written = <String>[];
  @override
  Future<void> write({required String key, String? value}) async {
    if (_failed &&
        (failAllAfterFailure || (value == null && failClearsAfterFailure))) {
      throw StateError('secure storage clear failed');
    }
    if (key == failKey &&
        (value != null || failClears) &&
        !(failOnce && _failed)) {
      _failed = true;
      throw StateError('secure storage write failed');
    }
    written.add(key);
    return super.write(key: key, value: value);
  }

  /// Puts a value in place without going through the failing [write].
  void seed(String key, String value) {
    super.write(key: key, value: value);
  }

  Future<Map<String, String>> kept() async => {
    for (final key in const [
      'wrf_address',
      'wrf_mnemonic',
      'wrf_private_key',
      'wrf_key_scheme',
      'wrf_login_private_key',
      'wrf_login_address',
    ])
      key: ?await read(key: key),
  };
}

/// Every slot storeKeys writes a value into, in order.
const _valueSlots = [
  'wrf_mnemonic',
  'wrf_private_key',
  'wrf_key_scheme',
  'wrf_login_private_key',
  'wrf_login_address',
  'wrf_address',
];

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

    for (final failKey in _valueSlots) {
      test(
        'a failed write of $failKey leaves no wallet and no secrets',
        () async {
          final failing = _FailingWriteStorage(failKey);
          final manager = KeyManager(
            biometric: BiometricService(client: FakeLocalAuthClient()),
            storage: failing,
          );
          await expectLater(
            manager.storeKeys(
              mnemonic: 'seed phrase',
              privateKey: '0xabc',
              address: 'wrf1testwallet0000000000',
            ),
            throwsA(isA<WalletSaveFailure>()),
          );
          expect(await manager.hasWallet(), isFalse);
          expect(await manager.getAddress(), isNull);
          // Rolled back: no half wallet's phrase or keys stay on the phone.
          expect(await failing.kept(), isEmpty);
        },
      );

      test(
        'a failed write of $failKey with a broken rollback still shows no wallet',
        () async {
          final failing = _FailingWriteStorage(
            failKey,
            failClearsAfterFailure: true,
          );
          final manager = KeyManager(
            biometric: BiometricService(client: FakeLocalAuthClient()),
            storage: failing,
          );
          await expectLater(
            manager.storeKeys(
              mnemonic: 'seed phrase',
              privateKey: '0xabc',
              address: 'wrf1testwallet0000000000',
            ),
            throwsA(isA<WalletSaveFailure>()),
          );
          expect(await manager.hasWallet(), isFalse);
          expect(await manager.getAddress(), isNull);
        },
      );
    }

    test('the error shown to the user is plain and keeps no detail', () {
      final failure = WalletSaveFailure(StateError('keystore said no'));
      expect(failure.message, contains('could not be saved'));
      expect(failure.message, isNot(contains('keystore')));
    });

    test(
      'if the old address cannot be cleared, the old wallet stays as it was',
      () async {
        final failing = _FailingWriteStorage('wrf_address', failClears: true);
        await failing.write(key: 'wrf_mnemonic', value: 'old phrase');
        await failing.write(key: 'wrf_private_key', value: '0xold');
        // Seed the old address past the failing fake.
        failing.seed('wrf_address', 'wrf1old');
        final manager = KeyManager(
          biometric: BiometricService(client: FakeLocalAuthClient()),
          storage: failing,
        );
        await expectLater(
          manager.storeKeys(
            mnemonic: 'new phrase',
            privateKey: '0xnew',
            address: 'wrf1new',
          ),
          throwsStateError,
        );
        expect(await manager.getAddress(), 'wrf1old');
        expect((await failing.kept())['wrf_private_key'], '0xold');
        expect(await manager.hasWallet(), isTrue);
      },
    );

    test('the address is written last', () async {
      final recording = _FailingWriteStorage('none');
      final manager = KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: recording,
      );
      await manager.storeKeys(
        mnemonic: 'seed phrase',
        privateKey: '0xabc',
        address: 'wrf1testwallet0000000000',
      );
      expect(recording.written.last, 'wrf_address');
    });

    Future<void> seedOldWallet(_FailingWriteStorage failing) async {
      failing
        ..seed('wrf_mnemonic', 'old phrase')
        ..seed('wrf_private_key', '0xold')
        ..seed('wrf_key_scheme', KeyManager.canonicalKeyScheme)
        ..seed('wrf_login_private_key', '0xoldlogin')
        ..seed('wrf_login_address', 'wrf1old')
        ..seed('wrf_jwt', 'old.jwt')
        ..seed('wrf_address', 'wrf1old');
    }

    Future<void> expectOldWalletIntact(
      KeyManager manager,
      _FailingWriteStorage failing,
    ) async {
      expect(await manager.hasWallet(), isTrue);
      expect(await manager.getAddress(), 'wrf1old');
      expect(await manager.canSignTransactions(), isTrue);
      expect(await manager.getPrivateKey(), '0xold');
      expect(await manager.getMnemonic(), 'old phrase');
      expect(await manager.getLoginPrivateKey(), '0xoldlogin');
      expect(await manager.getLoginAddress(), 'wrf1old');
      expect(await failing.read(key: 'wrf_jwt'), 'old.jwt');
    }

    for (final failKey in _valueSlots) {
      for (final once in [true, false]) {
        final kind = once ? 'a one-off' : 'a lasting';
        test('existing wallet + $kind failure writing $failKey: the old '
            'wallet is kept', () async {
          final failing = _FailingWriteStorage(failKey, failOnce: once);
          await seedOldWallet(failing);
          final manager = KeyManager(
            biometric: BiometricService(client: FakeLocalAuthClient()),
            storage: failing,
          );
          await expectLater(
            manager.storeKeys(
              mnemonic: 'new phrase',
              privateKey: '0xnew',
              address: 'wrf1new',
            ),
            throwsA(isA<WalletSaveFailure>()),
          );
          if (!once && failKey == 'wrf_address') {
            // The address slot cannot be written at all, so the cleared
            // address cannot come back. Every old secret is still there and
            // nothing new is mixed in; no wallet is shown.
            expect(await manager.hasWallet(), isFalse);
            expect(await failing.read(key: 'wrf_mnemonic'), 'old phrase');
            expect(await failing.read(key: 'wrf_private_key'), '0xold');
            expect(
              await failing.read(key: 'wrf_login_private_key'),
              '0xoldlogin',
            );
          } else {
            await expectOldWalletIntact(manager, failing);
          }
        });
      }
    }

    test('existing wallet + a store that breaks for good: no mixed wallet is '
        'shown', () async {
      // The phrase slot already holds the new phrase when the private key
      // write fails, and nothing can be written back.
      final failing = _FailingWriteStorage(
        'wrf_private_key',
        failAllAfterFailure: true,
      );
      await seedOldWallet(failing);
      final manager = KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: failing,
      );
      await expectLater(
        manager.storeKeys(
          mnemonic: 'new phrase',
          privateKey: '0xnew',
          address: 'wrf1new',
        ),
        throwsA(isA<WalletSaveFailure>()),
      );
      expect(await manager.getAddress(), isNull);
      expect(await manager.hasWallet(), isFalse);
      // The old private key was never overwritten and is not deleted.
      expect(await failing.read(key: 'wrf_private_key'), '0xold');
    });

    test(
      'a failed save over a half-saved address puts it back as it was',
      () async {
        final failing = _FailingWriteStorage('wrf_private_key');
        failing.seed('wrf_address', 'wrf1old');
        final manager = KeyManager(
          biometric: BiometricService(client: FakeLocalAuthClient()),
          storage: failing,
        );
        await expectLater(
          manager.storeKeys(
            mnemonic: 'seed phrase',
            privateKey: '0xnew',
            address: 'wrf1new',
          ),
          throwsA(isA<WalletSaveFailure>()),
        );
        expect(await manager.getAddress(), 'wrf1old');
        expect(await manager.hasWallet(), isFalse);
        expect(await failing.read(key: 'wrf_mnemonic'), isNull);
      },
    );

    test('a successful save over an old wallet replaces it', () async {
      final failing = _FailingWriteStorage('none');
      await seedOldWallet(failing);
      final manager = KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: failing,
      );
      await manager.storeKeys(
        mnemonic: 'new phrase',
        privateKey: '0xnew',
        address: 'wrf1new',
      );
      expect(await manager.getAddress(), 'wrf1new');
      expect(await manager.getPrivateKey(), '0xnew');
      expect(await failing.read(key: 'wrf_jwt'), isNull);
    });

    test('an address without a private key is not a wallet', () async {
      await storage.write(key: 'wrf_address', value: 'wrf1halfsaved');
      final manager = KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: storage,
      );
      expect(await manager.hasWallet(), isFalse);
    });

    test('a legacy install (no scheme marker) is still a wallet', () async {
      await storage.write(key: 'wrf_address', value: 'wrf1legacy');
      await storage.write(key: 'wrf_private_key', value: '0xlegacy');
      final manager = KeyManager(
        biometric: BiometricService(client: FakeLocalAuthClient()),
        storage: storage,
      );
      expect(await manager.hasWallet(), isTrue);
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
