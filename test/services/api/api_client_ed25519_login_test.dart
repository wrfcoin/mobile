import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/ed25519_wallet_login.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/transparent_transfer_authorization.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../../test_helpers/fakes.dart';

String _hex(Iterable<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String hex) => <int>[
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String _strip0x(String v) =>
    v.startsWith('0x') || v.startsWith('0X') ? v.substring(2) : v;

/// In-process stand-in for the backend: the ed25519 wallet-login contract of
/// backend#1208 (`wallet-auth-service.ts`) and the owner-bound wallet routes
/// of backend#1197/#1199 (JWT `sub` must equal the address / `from`).
class _FakeBackend implements HttpClientAdapter {
  static const origin = 'https://wallet.test';
  static const chainId = 777;
  static const network = 'testnet';

  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Map<String, String>> _challenges = {};
  final Map<String, Map<String, String>> tokens = {};
  final List<String> loginRejections = <String>[];
  int _counter = 0;

  /// Overrides the address line of the next issued challenge.
  String? challengeAddressOverride;

  /// Replaces the whole issued `message` (a hostile or compromised backend).
  String? messageOverride;

  static String ed25519Address(List<int> pubkey) =>
      '0x${_hex(SHA3Digest(256).process(Uint8List.fromList(pubkey)).take(20))}';

  /// Mirrors backend#1208 `buildEd25519WalletLoginMessage`.
  static String buildMessage({
    required String address,
    required String nonce,
    required String issuedAt,
    required String expirationTime,
  }) =>
      'wrfcoin_wallet_login_ed25519_v1\n'
      '${Uri.parse(origin).host} wants you to sign in with your WRFCoin ed25519 account:\n'
      '${address.toLowerCase()}\n\nSign in to WRFCoin Testnet.\n\n'
      'URI: $origin\nVersion: 1\nScheme: ed25519\nChain ID: $chainId\n'
      'Network: $network\nNonce: $nonce\nIssued At: $issuedAt\n'
      'Expiration Time: $expirationTime';

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    final body = options.data is Map
        ? Map<String, dynamic>.from(options.data as Map)
        : <String, dynamic>{};

    if (options.method == 'GET' && path.contains('/auth/nonce/')) {
      return _nonce(path.split('/').last, options.uri.queryParameters);
    }
    if (options.method == 'POST' && path.endsWith('/auth/wallet-login')) {
      return _login(body);
    }
    final claims = tokens[_bearer(options)];
    if (options.method == 'GET' && path.endsWith('/nonce')) {
      final segments = path.split('/');
      final address = segments[segments.length - 2];
      if (claims == null) return _json(401, {'error': 'unauthorized'});
      if (claims['sub'] != address) return _json(403, {'error': 'forbidden'});
      return _json(200, {
        'success': true,
        'data': {'nonce': '7'},
      });
    }
    if (options.method == 'POST' && path.endsWith('/wallet/send')) {
      if (claims == null) return _json(401, {'error': 'unauthorized'});
      if (claims['sub'] != body['from']) {
        return _json(403, {'error': 'forbidden'});
      }
      final pubkey = _unhex(body['auth_pubkey'] as String);
      if (ed25519Address(pubkey) != body['from']) {
        return _json(403, {'error': 'key does not own from'});
      }
      final preimage = transparentTransferAuthorizationMessage(
        chainId: TransferSigningDomain.configured.chainId,
        networkId: 'testnet',
        from: body['from'] as String,
        to: body['to'] as String,
        amountBaseUnits: int.parse(body['amount'] as String),
        nonce: int.parse(body['nonce'] as String),
      );
      if (!await _verify(pubkey, body['auth_signature'] as String, preimage)) {
        return _json(400, {'error': 'bad transfer signature'});
      }
      return _json(202, {'hash': '0xtx', 'status': 'submitted'});
    }
    return _json(404, {'error': 'not found'});
  }

  ResponseBody _nonce(String address, Map<String, String> query) {
    if (query['scheme'] != 'ed25519') {
      // The EVM challenge is SIWE text for a checksummed address.
      final nonce = 'evm-${_counter++}';
      return _json(200, {
        'success': true,
        'data': {
          'nonce': nonce,
          'message':
              'wallet.test wants you to sign in with your Ethereum account:\n$address\n\nNonce: $nonce',
          'issuedAt': '2026-09-23T00:00:00.000Z',
          'expirationTime': '2026-09-23T00:05:00.000Z',
        },
      });
    }
    final nonce = 'ed-${_counter++}-${DateTime.now().microsecondsSinceEpoch}';
    final issuedAt = DateTime.now().toUtc().toIso8601String();
    final expirationTime = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String();
    final message = buildMessage(
      address: challengeAddressOverride ?? address,
      nonce: nonce,
      issuedAt: issuedAt,
      expirationTime: expirationTime,
    );
    final issued = messageOverride ?? message;
    _challenges['ed25519:${address.toLowerCase()}'] = {
      'nonce': nonce,
      'message': issued,
    };
    return _json(200, {
      'success': true,
      'data': {
        'nonce': nonce,
        'message': issued,
        'issuedAt': issuedAt,
        'expirationTime': expirationTime,
        'scheme': 'ed25519',
        'network': network,
      },
    });
  }

  Future<ResponseBody> _login(Map<String, dynamic> body) async {
    ResponseBody reject(String reason) {
      loginRejections.add(reason);
      return _json(401, {'error': reason});
    }

    if (body['scheme'] != 'ed25519') {
      // An EVM signature can never mint a session for an ed25519 chain
      // address: ecrecover cannot yield a SHA3(ed25519 pubkey) address.
      return reject('evm login for a non-EVM key');
    }
    final pubkey = _strip0x('${body['pubkey'] ?? ''}');
    final signature = _strip0x('${body['signature'] ?? ''}');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(pubkey)) {
      return reject('bad pubkey');
    }
    if (!RegExp(r'^[0-9a-fA-F]{128}$').hasMatch(signature)) {
      return reject('bad signature format');
    }
    final address = '${body['address']}'.toLowerCase();
    if (ed25519Address(_unhex(pubkey)) != address) {
      return reject('address does not match the ed25519 public key');
    }
    final challenge = _challenges.remove('ed25519:$address');
    if (challenge == null || challenge['nonce'] != body['nonce']) {
      return reject('nonce expired or not found');
    }
    if (!await _verify(
      _unhex(pubkey),
      signature,
      utf8.encode(challenge['message']!),
    )) {
      return reject('invalid wallet signature');
    }
    final jwt = 'jwt-${_counter++}';
    tokens[jwt] = {'sub': address, 'wallet_scheme': 'ed25519'};
    return _json(200, {
      'success': true,
      'data': {'jwt': jwt, 'refreshToken': 'refresh-$jwt', 'expiresIn': 900},
    });
  }

  static Future<bool> _verify(
    List<int> pubkey,
    String signatureHex,
    List<int> message,
  ) {
    return Ed25519().verify(
      message,
      signature: Signature(
        _unhex(signatureHex),
        publicKey: SimplePublicKey(pubkey, type: KeyPairType.ed25519),
      ),
    );
  }

  static String? _bearer(RequestOptions options) {
    final header = options.headers['Authorization'] as String?;
    return header?.startsWith('Bearer ') == true ? header!.substring(7) : null;
  }

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  final vector = jsonDecode(
    File('contract-fixtures/wallet-key-scheme-vector.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final vectorAddress = vector['address'] as String;
  final vectorPubkey = vector['ed25519_public_key_hex'] as String;
  const recipient = '0x2222222222222222222222222222222222222222';

  late _FakeBackend backend;
  late KeyManager keys;
  late AuthHandoffController handoff;
  late ApiClient client;
  late WalletCredentials wallet;

  Future<void> storeVectorWallet({String? addressOverride}) async {
    wallet = await WalletSetupService().importFromMnemonic(
      vector['mnemonic'] as String,
    );
    // Exactly what import_wallet_screen stores.
    await keys.storeKeys(
      mnemonic: wallet.mnemonic,
      privateKey: wallet.privateKey,
      address: addressOverride ?? wallet.address,
      keyScheme: wallet.keyScheme,
      loginPrivateKey: wallet.loginPrivateKey,
      loginAddress: wallet.loginAddress,
    );
  }

  setUp(() {
    // Each test is a fresh device: reset the in-isolate login ledger
    // (mobile#313), which otherwise spans the tests in this file.
    LoginAttemptGuard.resetIsolateStateForTest();
    backend = _FakeBackend();
    keys = KeyManager(
      biometric: BiometricService(
        client: FakeLocalAuthClient(authenticateResult: true),
      ),
      storage: InMemoryKeyValueStorage(),
    );
    handoff = AuthHandoffController();
    final authDio = Dio(BaseOptions(baseUrl: 'https://auth.invalid/api'))
      ..httpClientAdapter = backend;
    client = ApiClient(
      authDio: authDio,
      keyManager: keys,
      authHandoff: handoff,
      ed25519LoginExpectation: const Ed25519LoginExpectation(
        origin: _FakeBackend.origin,
        chainId: '777',
        network: 'testnet',
      ),
    );
    client.dio.options.baseUrl = 'https://auth.invalid/api';
    client.dio.httpClientAdapter = backend;
  });

  Map<String, dynamic> loginBody() => Map<String, dynamic>.from(
    backend.requests
            .singleWhere((r) => r.uri.path.endsWith('/auth/wallet-login'))
            .data
        as Map,
  );

  test('vector wallet stores no separate secp256k1 login identity', () async {
    await storeVectorWallet();
    expect(wallet.loginPrivateKey, isNull);
    expect(wallet.loginAddress, isNull);
    expect(await keys.getLoginAddress(), vectorAddress);
  });

  test('end to end: vector wallet logs in with ed25519 then nonce and send pass the owner checks', () async {
    await storeVectorWallet();
    // mobile#320: the login is the user's Sign in, never a side effect.
    expect(await client.signInNow(), isTrue);

    final signer = await Ed25519TransferSigner.fromSeedHex(
      (await keys.getPrivateKey())!,
    );
    final result = await WalletRemoteDataSource(client.dio).sendTransaction(
      from: vectorAddress,
      to: recipient,
      amountBaseUnits: '150000000',
      signer: signer,
    );

    expect(result['status'], 'submitted');
    expect(backend.loginRejections, isEmpty);
    expect(backend.requests.map((r) => '${r.method} ${r.uri.path}').toList(), [
      'GET /api/auth/nonce/$vectorAddress',
      'POST /api/auth/wallet-login',
      'GET /api/wallet/$vectorAddress/nonce',
      'POST /api/wallet/send',
    ]);
    expect(backend.requests.first.uri.queryParameters, {'scheme': 'ed25519'});

    final body = loginBody();
    expect(body.keys.toSet(), {
      'scheme',
      'address',
      'pubkey',
      'signature',
      'nonce',
    });
    expect(body['scheme'], 'ed25519');
    expect(body['address'], vectorAddress);
    expect(body['pubkey'], vectorPubkey);
    expect(body['signature'], matches(RegExp(r'^[0-9a-f]{128}$')));

    final jwt = await keys.getAuthToken();
    expect(backend.tokens[jwt], {
      'sub': vectorAddress,
      'wallet_scheme': 'ed25519',
    });
    expect(await keys.getAuthWalletScheme(), KeyManager.ed25519AuthScheme);
    for (final r in backend.requests.skip(2)) {
      expect(r.headers['Authorization'], 'Bearer $jwt');
    }
  });

  test('an ed25519-slip10 wallet never takes the EVM login path', () async {
    await storeVectorWallet();
    expect(await client.signInNow(), isTrue);

    final nonceRequests = backend.requests.where(
      (r) => r.uri.path.contains('/auth/nonce/'),
    );
    expect(nonceRequests, hasLength(1));
    expect(nonceRequests.single.uri.queryParameters['scheme'], 'ed25519');
    final body = loginBody();
    expect(body['scheme'], 'ed25519');
    // No 0x-prefixed 65-byte personal_sign signature.
    expect(body['signature'], isNot(startsWith('0x')));
    expect((body['signature'] as String).length, 128);
    expect(handoff.requiresWalletConnect, isFalse);
  });

  test('an install that still holds a legacy secp256k1 login identity logs in as the chain address', () async {
    wallet = await WalletSetupService().importFromMnemonic(
      vector['mnemonic'] as String,
    );
    final legacyLoginKey = WalletSetupService().legacyPrivateKeyFromMnemonic(
      wallet.mnemonic,
    );
    await keys.storeKeys(
      mnemonic: wallet.mnemonic,
      privateKey: wallet.privateKey,
      address: wallet.address,
      loginPrivateKey: legacyLoginKey,
      loginAddress: '0x9858effd232b4033e47d90003d41ec34ecaeda94',
    );
    // A pre-#1208 session whose sub is the secp256k1 login address.
    await keys.storeAuthSession(
      jwt: 'legacy-evm-jwt',
      refreshToken: 'legacy-evm-refresh',
      expiresInSeconds: 900,
    );
    expect(await client.signInNow(), isTrue);

    final signer = await Ed25519TransferSigner.fromSeedHex(wallet.privateKey);
    final result = await WalletRemoteDataSource(client.dio).sendTransaction(
      from: vectorAddress,
      to: recipient,
      amountBaseUnits: '1',
      signer: signer,
    );

    expect(result['status'], 'submitted');
    expect(loginBody()['address'], vectorAddress);
    expect(
      backend.requests.where((r) => r.uri.path.endsWith('/auth/refresh')),
      isEmpty,
    );
    expect(await keys.getRefreshToken(), isNot('legacy-evm-refresh'));
  });

  test(
    'refuses a challenge that is not an ed25519 login for this address',
    () async {
      await storeVectorWallet();
      backend.challengeAddressOverride =
          '0x1111111111111111111111111111111111111111';

      expect(await client.signInNow(), isFalse);
      expect(
        backend.requests.where(
          (r) => r.uri.path.endsWith('/auth/wallet-login'),
        ),
        isEmpty,
      );
    },
  );

  test('a backend that offers a transfer preimage as the login message gets nothing signed', () async {
    await storeVectorWallet();
    // A preimage that survives the JSON string round trip byte for byte
    // (the backend#1208 review probe amount).
    final preimage = transparentTransferAuthorizationMessage(
      chainId: '777',
      networkId: 'testnet',
      from: vectorAddress,
      to: recipient,
      amountBaseUnits: 547599908735,
      nonce: 7,
    );
    backend.messageOverride = utf8.decode(preimage);

    expect(await client.signInNow(), isFalse);
    expect(
      backend.requests.where((r) => r.uri.path.endsWith('/auth/wallet-login')),
      isEmpty,
    );
    expect(handoff.requiresWalletConnect, isTrue);
    expect(await keys.getAuthToken(), isNull);
  });

  test('a stored address that the seed does not derive is refused before any request', () async {
    await storeVectorWallet(
      addressOverride: '0x1111111111111111111111111111111111111111',
    );

    expect(await client.signInNow(), isFalse);
    expect(backend.requests, isEmpty);
    expect(handoff.requiresWalletConnect, isTrue);
    expect(handoff.reason, AuthHandoffReason.unsupportedWallet);
  });
}
