import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';
import 'package:wrfcoin_mobile/features/faucet/data/datasources/faucet_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../../test_helpers/fakes.dart';

const _seed =
    '73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883';

class _Transport implements HttpClientAdapter {
  _Transport(this.failure);
  final Object failure;
  final List<RequestOptions> writes = [];
  int refreshes = 0;
  int reads = 0;

  ResponseBody json(Object data, int status) => ResponseBody.fromString(
    jsonEncode(data),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == ApiConstants.authRefresh) {
      refreshes++;
      return json({'jwt': 'fresh-access', 'refreshToken': 'refresh'}, 200);
    }
    if (options.method == 'GET' && options.path.endsWith('/nonce')) {
      return json({'nonce': '5'}, 200);
    }
    if (options.method == 'GET') {
      reads++;
      return reads == 1 ? json({'error': 'temporary'}, 503) : json({}, 200);
    }
    writes.add(options);
    if (writes.length > 1) {
      return json({
        'hash': 'duplicate',
        'txHash': 'duplicate',
        'amount': '1',
      }, 202);
    }
    if (failure is int) return json({'error': 'ambiguous'}, failure as int);
    throw DioException(
      requestOptions: options,
      type: failure as DioExceptionType,
    );
  }
}

void main() {
  for (final action in ['claim', 'send']) {
    for (final failure in [
      500,
      503,
      401,
      409,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      test('$action does not replay after $failure', () async {
        final transport = _Transport(failure);
        final storage = InMemoryKeyValueStorage();
        // No expiry field: this synthetic cached session is independent of time.
        await storage.write(key: 'wrf_jwt', value: 'cached-access');
        await storage.write(key: 'wrf_refresh_token', value: 'refresh');
        await storage.write(
          key: 'wrf_address',
          value: '0x2222222222222222222222222222222222222222',
        );
        final keys = KeyManager(
          biometric: BiometricService(client: FakeLocalAuthClient()),
          storage: storage,
        );
        final authDio = Dio()..httpClientAdapter = transport;
        // Use the production constructor/interceptor chain, replacing only I/O.
        final client = ApiClient(keyManager: keys, authDio: authDio);
        client.dio.options.baseUrl = 'https://one-shot.invalid/api';
        client.dio.httpClientAdapter = transport;
        authDio.options.baseUrl = 'https://one-shot.invalid/api';
        addTearDown(() => client.dio.close(force: true));
        addTearDown(() => authDio.close(force: true));

        Future<Object> submit() async {
          if (action == 'claim') {
            return FaucetRemoteDataSource(client.dio).claim(
              walletAddress: '0x2222222222222222222222222222222222222222',
              challengeId: 'synthetic-challenge',
              answer: 19,
            );
          }
          final signer = await Ed25519TransferSigner.fromSeedHex(_seed);
          return WalletRemoteDataSource(client.dio).sendTransaction(
            from: WalletSetupService().chainAddressFromEd25519(
              signer.publicKey,
            ),
            to: '0x2222222222222222222222222222222222222222',
            amountBaseUnits: '1',
            signer: signer,
          );
        }

        await expectLater(submit(), throwsA(isA<DioException>()));
        expect(transport.writes, hasLength(1));
        expect(transport.refreshes, 0, reason: 'No 401 refresh-and-replay');
        expect(
          transport.writes.single.headers['Authorization'],
          'Bearer cached-access',
        );
      });
    }
  }

  test('ordinary reads retain transient retry', () async {
    final transport = _Transport(503);
    final client = ApiClient();
    client.dio.options.baseUrl = 'https://one-shot.invalid/api';
    client.dio.httpClientAdapter = transport;
    addTearDown(() => client.dio.close(force: true));
    final response = await client.dio.get('/ordinary-read');
    expect(response.statusCode, 200);
    expect(transport.reads, 2);
    expect(transport.writes, isEmpty);
  });
}
