// Live end-to-end send against a LOCAL stack (mobile#286).
//
// Drives the app's own code, not a re-implementation. The ed25519 login runs
// through ApiClient/_AuthSessionCoordinator, the nonce read and the signed
// base-unit transfer through WalletRemoteDataSource.sendTransaction, and the
// wallet comes from WalletSetupService/KeyManager. Real HTTP goes to a real
// backend, which relays to a real core4 launch_api. Settlement is read back from
// core4 itself.
//
// Skipped unless WRFCOIN_E2E_BASE_URL is set. It is NOT for the live testnet:
// the test mines blocks through the operator route. Run it only against a
// throwaway local node whose producer payout is the test wallet, so coinbase
// funds it. The backend must run with WRFCOIN_CHAIN_ID/WRFCOIN_NETWORK_ID equal
// to the node's and WRFCOIN_WALLET_AUTH_ORIGIN equal to this base URL's origin.
//
// Rerun only on a fresh node, or once 10 minutes have passed. The backend relays
// every send with one core4 Contributor token, and core4 allows 2 legacy
// submits per 60 s per token. The two tests here spend exactly that budget. A
// valid send that then hits the 429 also reserves its from+nonce for the
// 10-minute replay TTL, so the retry returns 409 REPLAY_REJECTED
// (wrfcoin/core4#3337).
//
//   WRFCOIN_E2E_BASE_URL        backend API base, e.g. http://127.0.0.1:18080/api
//   WRFCOIN_E2E_CORE4_URL       core4 launch_api, e.g. http://127.0.0.1:18577
//   WRFCOIN_E2E_CORE4_OPERATOR  core4 operator token (mines the settling block)
//   WRFCOIN_E2E_CORE4_READER    core4 reader token (reads balances/nonces)
//   WRFCOIN_E2E_MINER           producer payout address the node mines to
//   WRFCOIN_E2E_MNEMONIC        optional; defaults to the key-scheme vector wallet
//
//   flutter test test/integration/local_stack_send_e2e_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/core/utils/wrf_units.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/ed25519_wallet_login.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../test_helpers/fakes.dart';
import '../test_helpers/local_stack_guard.dart';

String _env(String key) => Platform.environment[key]?.trim() ?? '';

final _baseUrl = _env('WRFCOIN_E2E_BASE_URL');
final _core4Url = _env('WRFCOIN_E2E_CORE4_URL');
final _operatorToken = _env('WRFCOIN_E2E_CORE4_OPERATOR');
final _readerToken = _env('WRFCOIN_E2E_CORE4_READER');
final _miner = _env('WRFCOIN_E2E_MINER');

Map<String, dynamic> _vector() => jsonDecode(
  File('contract-fixtures/wallet-key-scheme-vector.json').readAsStringSync(),
) as Map<String, dynamic>;

String _randomAddress() {
  final rng = Random.secure();
  return '0x${List.generate(20, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

void main() {
  // Each test is a fresh device: reset the in-isolate login ledger
  // (mobile#313), which otherwise spans the tests in this file.
  setUp(LoginAttemptGuard.resetIsolateStateForTest);

  final skip = _baseUrl.isEmpty
      ? 'WRFCOIN_E2E_BASE_URL not set; local-stack E2E only'
      : null;

  late Dio core4;
  late KeyManager keys;
  late ApiClient client;
  late WalletCredentials wallet;

  Future<Map<String, dynamic>> account(String address) async {
    final r = await core4.get<dynamic>('/addresses/$address');
    if (r.statusCode == 404) {
      return const {'spendable_balance': '0', 'nonce': '0'};
    }
    expect(r.statusCode, 200, reason: 'core4 /addresses/$address: ${r.data}');
    return Map<String, dynamic>.from((r.data as Map)['data'] as Map);
  }

  /// The sender's chain nonce as core4 reports it. It must be an existing
  /// account and an unsigned integer, so a missing or null nonce can never
  /// compare equal to itself.
  Future<BigInt> nonceOf(String address) async {
    final r = await core4.get<dynamic>('/addresses/$address');
    expect(r.statusCode, 200, reason: 'core4 /addresses/$address: ${r.data}');
    final nonce = ((r.data as Map)['data'] as Map)['nonce'];
    expect(nonce, isNotNull, reason: 'core4 returned no nonce for $address');
    expect('$nonce', matches(RegExp(r'^\d+$')), reason: 'nonce: $nonce');
    return BigInt.parse('$nonce');
  }

  BigInt balanceOf(Map<String, dynamic> a) =>
      BigInt.parse('${a['spendable_balance'] ?? a['balance'] ?? '0'}');

  Future<void> mine() async {
    final r = await core4.post<dynamic>(
      '/blocks/mine',
      data: {'miner_address': _miner},
      options: Options(headers: {'Authorization': 'Bearer $_operatorToken'}),
    );
    expect(r.statusCode, anyOf(200, 201), reason: 'mine: ${r.data}');
  }

  WalletRemoteDataSource datasource({TransferSigningDomain? domain}) =>
      WalletRemoteDataSource(
        client.dio,
        signingDomain: domain ?? TransferSigningDomain.configured,
      );

  setUpAll(() async {
    if (skip != null) return;
    for (final (name, value) in [
      ('WRFCOIN_E2E_CORE4_URL', _core4Url),
      ('WRFCOIN_E2E_CORE4_OPERATOR', _operatorToken),
      ('WRFCOIN_E2E_CORE4_READER', _readerToken),
      ('WRFCOIN_E2E_MINER', _miner),
    ]) {
      if (value.isEmpty) fail('$name must be set with WRFCOIN_E2E_BASE_URL');
    }
    // Before any request: an operator token plus a real URL must never mine
    // on a real chain.
    for (final (name, url) in [
      ('WRFCOIN_E2E_BASE_URL', _baseUrl),
      ('WRFCOIN_E2E_CORE4_URL', _core4Url),
    ]) {
      final reason = nonLoopbackReason(name, url);
      if (reason != null) fail(reason);
    }
    core4 = Dio(
      BaseOptions(
        baseUrl: _core4Url,
        headers: {'Authorization': 'Bearer $_readerToken'},
        validateStatus: (_) => true,
      ),
    );

    final mnemonic = _env('WRFCOIN_E2E_MNEMONIC').isNotEmpty
        ? _env('WRFCOIN_E2E_MNEMONIC')
        : _vector()['mnemonic'] as String;
    wallet = await WalletSetupService().importFromMnemonic(mnemonic);
    keys = KeyManager(
      biometric: BiometricService(
        client: FakeLocalAuthClient(authenticateResult: true),
      ),
      storage: InMemoryKeyValueStorage(),
    );
    // Exactly what import_wallet_screen stores.
    await keys.storeKeys(
      mnemonic: wallet.mnemonic,
      privateKey: wallet.privateKey,
      address: wallet.address,
      keyScheme: wallet.keyScheme,
      loginPrivateKey: wallet.loginPrivateKey,
      loginAddress: wallet.loginAddress,
    );
    client = ApiClient(
      authDio: Dio(BaseOptions(baseUrl: _baseUrl)),
      keyManager: keys,
      authHandoff: AuthHandoffController(),
      ed25519LoginExpectation: Ed25519LoginExpectation(
        origin: Ed25519LoginExpectation.originOf(_baseUrl)!,
        chainId: TransferSigningDomain.configured.chainId,
        network: TransferSigningDomain.configured.networkId,
      ),
    );
    client.dio.options.baseUrl = _baseUrl;
  });

  test('ed25519 login -> nonce -> signed base-unit transfer -> accepted and settled by core4', () async {
    final from = wallet.address;
    final to = _randomAddress();
    final amount = wrfDisplayToBaseUnits('1.5')!;
    expect(amount, '150000000');

    final senderBefore = await account(from);
    expect(
      balanceOf(senderBefore),
      greaterThanOrEqualTo(BigInt.parse(amount)),
      reason: 'fund $from on the local node first',
    );
    final nonceBefore = BigInt.parse('${senderBefore['nonce']}');

    // The app's nonce read, via the owner-bound backend route (JWT sub).
    expect(await datasource().getAccountNonce(from), nonceBefore.toString());
    expect(await keys.getAuthWalletScheme(), KeyManager.ed25519AuthScheme);

    final signer = await Ed25519TransferSigner.fromSeedHex(
      (await keys.getPrivateKey())!,
    );
    final result = await datasource().sendTransaction(
      from: from,
      to: to,
      amountBaseUnits: amount,
      signer: signer,
    );
    expect(result['status'], 'submitted');
    expect(result['hash'], isA<String>());
    // ignore: avoid_print
    print('E2E submitted tx ${result['hash']} $from -> $to $amount base units');

    await mine();

    final recipientAfter = await account(to);
    final senderAfter = await account(from);
    expect(balanceOf(recipientAfter), BigInt.parse(amount));
    expect(BigInt.parse('${senderAfter['nonce']}'), nonceBefore + BigInt.one);
    expect(
      await datasource().getAccountNonce(from),
      (nonceBefore + BigInt.one).toString(),
    );
    // ignore: avoid_print
    print(
      'E2E settled: recipient=${balanceOf(recipientAfter)} '
      'sender nonce $nonceBefore -> ${senderAfter['nonce']} '
      'sender balance ${balanceOf(senderBefore)} -> ${balanceOf(senderAfter)}',
    );
  }, skip: skip);

  test('a transfer signed for another network is rejected by core4 and moves nothing', () async {
    final from = wallet.address;
    final to = _randomAddress();
    final nonceBefore = await nonceOf(from);
    final signer = await Ed25519TransferSigner.fromSeedHex(
      (await keys.getPrivateKey())!,
    );

    await expectLater(
      datasource(
        domain: const TransferSigningDomain(
          chainId: '777',
          networkId: 'mainnet',
        ),
      ).sendTransaction(
        from: from,
        to: to,
        amountBaseUnits: '1',
        signer: signer,
      ),
      // core4's verdict relayed by the backend, not a backend-side refusal.
      throwsA(
        isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 400)
            .having(
              (e) => ((e.response?.data as Map)['error'] as Map)['code'],
              'code',
              'AUTHORIZATION_INVALID',
            ),
      ),
    );
    await mine();
    expect(balanceOf(await account(to)), BigInt.zero);
    expect(await nonceOf(from), nonceBefore);
  }, skip: skip);
}
