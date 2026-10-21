import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../test_helpers/fakes.dart';

void main() {
  // Each test is a fresh device: reset the in-isolate login ledger
  // (mobile#313), which otherwise spans the tests in this file.
  setUp(LoginAttemptGuard.resetIsolateStateForTest);

  test('legacy wallet signs the backend-issued message byte-for-byte', () async {
    const privateKey =
        '0x0000000000000000000000000000000000000000000000000000000000000002';
    const address = '0x2b5ad5c4795c026514f8317c7a215e218dccd6cf';
    const message = 'wallet.test wants you to sign in with your Ethereum account:\n'
        '0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF\n\n'
        'Sign in to WRFCoin Testnet.\n\nURI: https://wallet.test\nVersion: 1\n'
        'Chain ID: 777\nNonce: nonce-legacy\nIssued At: 2026-09-19T00:00:00.000Z\n'
        'Expiration Time: 2026-09-19T00:05:00.000Z';
    const backendVerifiedSignature = '0x0360e2f11502d4464a5e2dbc672c98ce44e8d1e1eb424746ca3ec69b289d8d3d4cc7ea0350090425948d73a92c3cdf667ea0c2d083a66bc9369fff863156b10f1c';
    final storage = InMemoryKeyValueStorage();
    final manager = KeyManager(
      biometric: BiometricService(client: FakeLocalAuthClient(authenticateResult: true)),
      storage: storage,
    );
    await manager.storeKeys(
      mnemonic: 'legacy wallet',
      privateKey: privateKey,
      address: address,
      loginPrivateKey: privateKey,
      loginAddress: address,
      keyScheme: KeyManager.legacyKeyScheme,
    );
    Map<String, dynamic>? loginBody;
    final authDio = Dio(BaseOptions(baseUrl: 'https://auth.invalid'));
    authDio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path.contains('/nonce')) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'nonce': 'nonce-legacy', 'message': message},
        ));
        return;
      }
      loginBody = Map<String, dynamic>.from(options.data as Map);
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'jwt': 'legacy-jwt', 'expiresIn': 900},
      ));
    }));

    final client = ApiClient(dio: Dio(), authDio: authDio, keyManager: manager);
    expect(await client.signInNow(), isTrue);
    expect(loginBody?['signature'], backendVerifiedSignature);
    expect(loginBody?['nonce'], 'nonce-legacy');
  });
}
