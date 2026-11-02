import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/utils/wrf_units.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transfer_fee.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/transparent_transfer_authorization.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

/// core4 golden `transparent_transfer_authorization_v2` signer secret
/// (signing_preimage_v2.json case 10). Public test data.
const _vectorSecretHex =
    '73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883';

List<int> _unhex(String hex) => <int>[
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

class _Recorder {
  final List<RequestOptions> requests = <RequestOptions>[];
  Object nonceResponse = const <String, dynamic>{'nonce': '5'};
  int nonceStatus = 200;

  Dio dio() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.method == 'GET') {
            if (nonceStatus != 200) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: nonceStatus,
                    data: const <String, dynamic>{'error': true},
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response(requestOptions: options, data: nonceResponse),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 202,
              data: const <String, dynamic>{
                'hash': '0xtx',
                'status': 'submitted',
                'settled': false,
              },
            ),
          );
        },
      ),
    );
    return dio;
  }
}

void main() {
  late Ed25519TransferSigner signer;
  late String from;
  const to = '0x2222222222222222222222222222222222222222';

  setUp(() async {
    signer = await Ed25519TransferSigner.fromSeedHex(_vectorSecretHex);
    from = WalletSetupService().chainAddressFromEd25519(signer.publicKey);
  });

  test(
    'fetches the account nonce then posts the exact signed base-unit body',
    () async {
      final recorder = _Recorder();
      final dataSource = WalletRemoteDataSource(recorder.dio());
      final amountBaseUnits = wrfDisplayToBaseUnits('1.5')!;

      final result = await dataSource.sendTransaction(
        from: from,
        to: to,
        amountBaseUnits: amountBaseUnits,
        signer: signer,
      );

      expect(result['status'], 'submitted');
      expect(recorder.requests.map((r) => '${r.method} ${r.path}'), [
        'GET /wallet/$from/nonce',
        'POST /wallet/send',
      ]);

      final body = Map<String, dynamic>.from(
        recorder.requests.last.data as Map,
      );
      // Exactly the fields backend parseSignedTransfer reads; no memo, no
      // display amount, no floating point.
      expect(body.keys.toSet(), {
        'from',
        'to',
        'amount',
        'nonce',
        'auth_pubkey',
        'auth_signature',
      });
      expect(body['from'], from);
      expect(body['to'], to);
      expect(body['amount'], '150000000');
      expect(body['nonce'], '5');

      final vector = jsonDecode(
        File('contract-fixtures/transparent-transfer-auth-vector.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        body['auth_pubkey'],
        (vector['case'] as Map)['signer_public_key_hex'],
      );

      // The signature verifies over the canonical preimage for exactly the
      // posted strings, at the configured 888/testnet domain.
      final message = transparentTransferAuthorizationMessage(
        chainId: '888',
        networkId: 'testnet',
        from: from,
        to: to,
        amountBaseUnits: 150000000,
        nonce: 5,
      );
      final valid = await Ed25519().verify(
        message,
        signature: Signature(
          _unhex(body['auth_signature'] as String),
          publicKey: SimplePublicKey(
            signer.publicKey,
            type: KeyPairType.ed25519,
          ),
        ),
      );
      expect(valid, isTrue);
    },
  );

  test('signs and posts the same lowercased recipient string', () async {
    final recorder = _Recorder();
    final dataSource = WalletRemoteDataSource(recorder.dio());
    const mixedCase = '0xABCDEFabcdef0000000000000000000000000001';

    await dataSource.sendTransaction(
      from: from.toUpperCase().replaceFirst('0X', '0x'),
      to: mixedCase,
      amountBaseUnits: '1',
      signer: signer,
    );

    final body = Map<String, dynamic>.from(recorder.requests.last.data as Map);
    expect(body['from'], from);
    expect(body['to'], mixedCase.toLowerCase());
    final expected = await buildSignedTransferBody(
      signer: signer,
      domain: TransferSigningDomain.configured,
      from: from,
      to: mixedCase.toLowerCase(),
      amountBaseUnits: '1',
      nonce: '5',
    );
    expect(body, expected);
  });

  group('backend and edge contract', () {
    test('the POST body is exactly SIGNED_TRANSFER_CONTRACT.fields', () async {
      final recorder = _Recorder();
      await WalletRemoteDataSource(recorder.dio()).sendTransaction(
        from: from,
        to: to,
        amountBaseUnits: '200000000',
        signer: signer,
      );
      final post = recorder.requests.singleWhere((r) => r.method == 'POST');
      expect(post.path, '/wallet/send');
      expect(post.uri.query, isEmpty, reason: 'the edge admits no query');
      final body = post.data as Map<String, String>;
      // backend wallet-transfer-contract.js SIGNED_TRANSFER_CONTRACT.fields.
      // No fee: the signature covers from|to|amount|nonce, and the node
      // declares the fee itself.
      expect(body.keys.toSet(), {
        'from',
        'to',
        'amount',
        'nonce',
        'auth_pubkey',
        'auth_signature',
      });
      // The same rules as backend parseSignedTransfer.
      final launchAddress = RegExp(r'^0x[0-9a-f]{40}$');
      expect(body['from'], matches(launchAddress));
      expect(body['to'], matches(launchAddress));
      expect(body['amount'], matches(RegExp(r'^[1-9]\d*$')));
      expect(BigInt.parse(body['amount']!) <= maxJsonSafeBaseUnits, isTrue);
      expect(body['nonce'], matches(RegExp(r'^\d{1,20}$')));
      expect(body['auth_pubkey'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(body['auth_signature'], matches(RegExp(r'^[0-9a-f]{128}$')));
    });

    test('sending calls only the nonce read and the send route', () async {
      final recorder = _Recorder();
      await WalletRemoteDataSource(recorder.dio()).sendTransaction(
        from: from,
        to: to,
        amountBaseUnits: '1',
        signer: signer,
      );
      expect(recorder.requests.map((r) => '${r.method} ${r.path}'), [
        'GET /wallet/$from/nonce',
        'POST /wallet/send',
      ]);
    });

    test('the fee read uses the admitted nonce path and no query', () async {
      final recorder = _Recorder();
      final quote = await WalletRemoteDataSource(recorder.dio())
          .getTransferFee('0xABCDEF0000000000000000000000000000000001');
      final read = recorder.requests.single;
      expect(read.method, 'GET');
      // The edge rule is ^/api/wallet/0x[0-9a-f]{40}/nonce$ with no query.
      expect(
        read.path,
        '/wallet/0xabcdef0000000000000000000000000000000001/nonce',
      );
      expect(read.uri.query, isEmpty);
      expect(quote.state, TransferFeeState.notReported);
    });

    test('a failed fee read is an error, never a quiet zero', () async {
      final recorder = _Recorder()..nonceStatus = 503;
      await expectLater(
        WalletRemoteDataSource(recorder.dio()).getTransferFee(from),
        throwsA(isA<DioException>()),
      );
    });
  });

  test('refuses to sign for an address the key does not control', () async {
    final recorder = _Recorder();
    final dataSource = WalletRemoteDataSource(recorder.dio());

    await expectLater(
      dataSource.sendTransaction(
        from: '0x1111111111111111111111111111111111111111',
        to: to,
        amountBaseUnits: '1',
        signer: signer,
      ),
      throwsStateError,
    );
    expect(recorder.requests, isEmpty);
  });

  test('a rejected nonce read (JWT sub != address) never posts', () async {
    final recorder = _Recorder()..nonceStatus = 403;
    final dataSource = WalletRemoteDataSource(recorder.dio());

    await expectLater(
      dataSource.sendTransaction(
        from: from,
        to: to,
        amountBaseUnits: '1',
        signer: signer,
      ),
      throwsA(isA<DioException>()),
    );
    expect(recorder.requests.map((r) => r.method), ['GET']);
  });

  test('a missing or non-integer nonce never posts', () async {
    for (final payload in [
      const <String, dynamic>{},
      const <String, dynamic>{'nonce': '1.5'},
      const <String, dynamic>{'nonce': -1},
    ]) {
      final recorder = _Recorder()..nonceResponse = payload;
      final dataSource = WalletRemoteDataSource(recorder.dio());
      await expectLater(
        dataSource.sendTransaction(
          from: from,
          to: to,
          amountBaseUnits: '1',
          signer: signer,
        ),
        throwsStateError,
        reason: '$payload',
      );
      expect(recorder.requests.map((r) => r.method), ['GET']);
    }
  });
}
