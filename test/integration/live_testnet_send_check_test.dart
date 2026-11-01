// Owner-run send check against the LIVE testnet (GO step 5, wallet send).
//
// NOT run by CI and not run by `flutter test` unless WRFCOIN_LIVE_SEND_CHECK=1:
// the script scripts/live_testnet_send_check.sh sets it. Drives the app's own
// code: WalletSetupService/KeyManager for the wallet, ApiClient's ed25519 login,
// WalletRemoteDataSource for the nonce read and the signed base-unit transfer.
// It never mines and holds no operator token; the only credential it takes is
// a core4 READER token (env only, never argv) to read the faucet and the
// recipient at the node.
//
// The STOP paths and the bounds (one send, <= 30 inclusion reads, faucet
// precondition first) live in test/test_helpers/live_send_check.dart and are
// unit tested with fakes in live_send_check_logic_test.dart.
//
//   WRFCOIN_LIVE_SEND_CHECK=1   required; anything else skips this file
//   WRFCOIN_LIVE_STEP           wallet | check | send
//   WRFCOIN_LIVE_BASE_URL       backend API base, e.g. https://wrfcoin.com/api
//   WRFCOIN_LIVE_AUTH_ORIGIN    the backend's WRFCOIN_WALLET_AUTH_ORIGIN
//   WRFCOIN_LIVE_MNEMONIC_FILE  0600 file holding the throwaway mnemonic (created if absent)
//   WRFCOIN_LIVE_NODE_URL       core4 launch_api reachable from this machine (Reader reads)
//   WRFCOIN_LIVE_READER_TOKEN   core4 Reader token (env only)
//   WRFCOIN_LIVE_FAUCET_ADDRESS the faucet's chain address (public)
//   WRFCOIN_LIVE_AMOUNT         display WRF to send (default 1)
//   WRFCOIN_LIVE_RECIPIENT      0x chain address to send to (required for `send`)
//   WRFCOIN_LIVE_SELF_TEST_RECIPIENT=1  explicit opt-in: send to a random throwaway instead
//   WRFCOIN_LIVE_FEE_BASE_UNITS fee reserve the sender must hold on top of the amount (default 1000000)
//
// Signing domain is pinned to chain 777 / testnet below (never a build-time
// override), the deployed WRFCOIN_CHAIN_ID / WRFCOIN_NETWORK_ID.
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/core/utils/wrf_units.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/ed25519_wallet_login.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../test_helpers/fakes.dart';
import '../test_helpers/live_send_check.dart';

String _env(String key) => Platform.environment[key]?.trim() ?? '';

final _enabled = _env('WRFCOIN_LIVE_SEND_CHECK') == '1';
final _step = _env('WRFCOIN_LIVE_STEP');
final _baseUrl = _env('WRFCOIN_LIVE_BASE_URL');
final _authOrigin = _env('WRFCOIN_LIVE_AUTH_ORIGIN');
final _mnemonicFile = _env('WRFCOIN_LIVE_MNEMONIC_FILE');
final _nodeUrl = _env('WRFCOIN_LIVE_NODE_URL');
final _readerToken = _env('WRFCOIN_LIVE_READER_TOKEN');
final _faucetAddress = _env('WRFCOIN_LIVE_FAUCET_ADDRESS').toLowerCase();
final _recipient = _env('WRFCOIN_LIVE_RECIPIENT');
final _selfTest = _env('WRFCOIN_LIVE_SELF_TEST_RECIPIENT') == '1';
final _feeReserve = _env('WRFCOIN_LIVE_FEE_BASE_UNITS').isEmpty
    ? defaultFeeReserveBaseUnits
    : _env('WRFCOIN_LIVE_FEE_BASE_UNITS');
final _amountDisplay =
    _env('WRFCOIN_LIVE_AMOUNT').isEmpty ? '1' : _env('WRFCOIN_LIVE_AMOUNT');

const _domain = TransferSigningDomain(
  chainId: liveChainId,
  networkId: liveNetworkId,
);

final List<String> _secrets = [];

// ignore: avoid_print
void _say(String line) => print('LIVE ${publicLine(line, _secrets)}');

String _randomAddress() {
  final rng = Random.secure();
  return '0x${List.generate(20, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

Future<WalletCredentials> _loadOrCreateWallet() async {
  final file = File(_mnemonicFile);
  final setup = WalletSetupService();
  if (file.existsSync()) {
    return setup.importFromMnemonic(file.readAsStringSync().trim());
  }
  final created = await setup.generateWallet();
  file.createSync(recursive: true);
  Process.runSync('chmod', ['600', file.path]); // restrict before the secret is written
  file.writeAsStringSync('${created.mnemonic}\n', flush: true);
  _say('created new throwaway wallet; mnemonic saved to ${file.path} (mode 600)');
  return created;
}

void main() {
  final skip = !_enabled
      ? 'WRFCOIN_LIVE_SEND_CHECK=1 not set; run scripts/live_testnet_send_check.sh'
      : (_step.isEmpty ? 'WRFCOIN_LIVE_STEP not set' : null);

  test('live testnet send check: $_step', () async {
    if (_mnemonicFile.isEmpty) fail('WRFCOIN_LIVE_MNEMONIC_FILE must be set');
    final wallet = await _loadOrCreateWallet();
    _secrets
      ..add(wallet.mnemonic)
      ..add(wallet.privateKey)
      ..add(_readerToken);
    _say('ADDRESS=${wallet.address}');
    if (_step == 'wallet') return;

    for (final (name, value) in [
      ('WRFCOIN_LIVE_BASE_URL', _baseUrl),
      ('WRFCOIN_LIVE_AUTH_ORIGIN', _authOrigin),
      ('WRFCOIN_LIVE_NODE_URL', _nodeUrl),
      ('WRFCOIN_LIVE_READER_TOKEN', _readerToken),
      ('WRFCOIN_LIVE_FAUCET_ADDRESS', _faucetAddress),
    ]) {
      if (value.isEmpty) fail('$name must be set');
    }
    if (!RegExp(r'^0x[0-9a-f]{40}$').hasMatch(_faucetAddress)) {
      fail('WRFCOIN_LIVE_FAUCET_ADDRESS must be a 0x-prefixed chain address');
    }

    LoginAttemptGuard.resetIsolateStateForTest();
    final keys = KeyManager(
      biometric: BiometricService(
        client: FakeLocalAuthClient(authenticateResult: true),
      ),
      storage: InMemoryKeyValueStorage(),
    );
    await keys.storeKeys(
      mnemonic: wallet.mnemonic,
      privateKey: wallet.privateKey,
      address: wallet.address,
      keyScheme: wallet.keyScheme,
      loginPrivateKey: wallet.loginPrivateKey,
      loginAddress: wallet.loginAddress,
    );
    // Name the failing request: method, path, status and a short body only.
    final logErrors = InterceptorsWrapper(
      onError: (e, handler) {
        final body = '${e.response?.data}';
        _say('HTTP ${e.requestOptions.method} ${e.requestOptions.path} -> '
            '${e.response?.statusCode} ${body.length > 300 ? body.substring(0, 300) : body}');
        handler.next(e);
      },
    );
    final authDio = Dio(BaseOptions(baseUrl: _baseUrl))..interceptors.add(logErrors);
    final client = ApiClient(
      authDio: authDio,
      keyManager: keys,
      authHandoff: AuthHandoffController(),
      ed25519LoginExpectation: Ed25519LoginExpectation(
        origin: _authOrigin,
        chainId: liveChainId,
        network: liveNetworkId,
      ),
    );
    final from = wallet.address;

    // Sign-in is explicit (the client never logs in on its own) and happens only after the
    // faucet precondition passed. The nonce reads and the ONE send then go through a
    // one-shot transport with a fixed bearer and NO retry interceptor: ApiClient's own Dio
    // retries timeouts and 5xx, which would turn one send into up to three POSTs.
    WalletRemoteDataSource? wallets;
    Future<bool> signIn() async {
      final ok = await client.signInNow();
      final jwt = await keys.getAuthToken();
      if (!ok || jwt == null) return false;
      _secrets.add(jwt);
      final oneShot = oneShotDio(baseUrl: _baseUrl, bearer: jwt)..interceptors.add(logErrors);
      wallets = WalletRemoteDataSource(oneShot, signingDomain: _domain);
      return true;
    }

    // The node, for Reader reads only. The token goes in a header, never argv/URL.
    final node = Dio(
      BaseOptions(
        baseUrl: _nodeUrl,
        headers: {'Authorization': 'Bearer $_readerToken'},
        validateStatus: (_) => true,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    Future<(int?, Object?)> readAddress(String address) async {
      try {
        final r = await node.get<dynamic>('/addresses/$address');
        return (r.statusCode, r.data);
      } on DioException {
        return (null, null);
      }
    }

    Future<BigInt?> ownNonce() async {
      try {
        return BigInt.parse(await wallets!.getAccountNonce(from));
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) return null; // not funded yet
        rethrow;
      }
    }

    final amount = wrfDisplayToBaseUnits(_amountDisplay);
    if (amount == null) fail('WRFCOIN_LIVE_AMOUNT is not a WRF amount');
    if (!RegExp(r'^\d+$').hasMatch(_feeReserve)) {
      fail('WRFCOIN_LIVE_FEE_BASE_UNITS must be an integer of base units');
    }
    // Resolved before any send so a missing recipient STOPs early.
    final String to;
    try {
      to = _step == 'send'
          ? resolveRecipient(
              recipient: _recipient,
              selfTest: _selfTest,
              random: _randomAddress,
              sender: from,
            )
          : '';
    } on LiveSendStop catch (stop) {
      _say('$stop');
      fail('$stop');
    }

    final check = LiveSendCheck(
      LiveSendPorts(
        readFaucet: () => readAddress(_faucetAddress),
        signIn: signIn,
        readOwnNonce: ownNonce,
        readOwnAccount: () => readAddress(from),
        send: (nonce) async {
          final signer = await Ed25519TransferSigner.fromSeedHex(
            (await keys.getPrivateKey())!,
          );
          _say('sending $amount base units ($_amountDisplay WRF) '
              'chain $liveChainId/$liveNetworkId $from -> $to at nonce $nonce');
          return sendOnce(
            wallets: wallets!,
            from: from,
            to: to,
            amountBaseUnits: amount,
            signer: signer,
          );
        },
        wait: () => Future<void>.delayed(const Duration(seconds: 20)),
        say: _say,
      ),
      amountBaseUnits: amount,
      feeReserveBaseUnits: _feeReserve,
    );

    try {
      if (_step == 'check') {
        await check.check();
      } else if (_step == 'send') {
        final result = await check.send();
        final (recipientStatus, recipientBody) = await readAddress(to);
        _say('recipient $to node read HTTP $recipientStatus '
            '${recipientBody is Map ? recipientBody['data'] : ''}');
        expect(result.settled, isTrue, reason: 'accepted but not settled');
      } else {
        fail('unknown WRFCOIN_LIVE_STEP=$_step');
      }
    } on LiveSendStop catch (stop) {
      _say('$stop');
      fail('$stop');
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 20)));
}
