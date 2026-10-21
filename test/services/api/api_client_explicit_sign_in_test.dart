// mobile#320: a wallet login happens only when the user asks for it.
//
// On the owner's phone the biometric prompt could never appear (the activity
// was not a FragmentActivity), so every automatic login died silently before
// the first request, and the wallet screen said "Session expired". With the
// prompt working, an automatic login would instead pop a biometric prompt on
// every wallet request. So automatic callers (wallet screen, sync, the 401
// retry) never unlock the key: they refresh a session if a refresh token
// exists and otherwise say "Not signed in". A login starts only from an
// explicit Sign in: 1 prompt, 1 nonce, 1 login per tap, and nothing more if
// the user cancels. The live backend bans every tailnet user for an hour
// after 5 failed logins in 15 minutes, so these tests count every request.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/ed25519_wallet_login.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../../test_helpers/fakes.dart';

const _origin = 'https://wallet.test';

/// The fake backend: the wallet-auth routes plus one owner-bound wallet
/// route. It counts every request.
class _Backend implements HttpClientAdapter {
  Completer<void>? loginGate;
  int nonceGets = 0;
  int loginPosts = 0;
  int refreshPosts = 0;
  final List<String?> walletAuthHeaders = <String?>[];
  final Set<String> validTokens = <String>{};
  int _counter = 0;

  static String _message(String address, String nonce) {
    final now = DateTime.now().toUtc();
    return 'wrfcoin_wallet_login_ed25519_v1\n'
        '${Uri.parse(_origin).host} wants you to sign in with your WRFCoin ed25519 account:\n'
        '$address\n\nSign in to WRFCoin Testnet.\n\n'
        'URI: $_origin\nVersion: 1\nScheme: ed25519\nChain ID: 777\n'
        'Network: testnet\nNonce: $nonce\n'
        'Issued At: ${now.toIso8601String()}\n'
        'Expiration Time: ${now.add(const Duration(minutes: 5)).toIso8601String()}';
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (options.method == 'GET' && path.contains('/auth/nonce/')) {
      nonceGets++;
      final address = path.split('/').last;
      final n = 'n-${_counter++}';
      return _json(200, {
        'success': true,
        'data': {
          'nonce': n,
          'message': _message(address, n),
          'scheme': 'ed25519',
        },
      });
    }
    if (options.method == 'POST' && path.endsWith('/auth/wallet-login')) {
      loginPosts++;
      await loginGate?.future;
      final jwt = 'jwt-${_counter++}';
      validTokens.add(jwt);
      return _json(200, {
        'success': true,
        'data': {'jwt': jwt, 'refreshToken': 'refresh-$jwt', 'expiresIn': 900},
      });
    }
    if (options.method == 'POST' && path.endsWith('/auth/refresh')) {
      refreshPosts++;
      final jwt = 'jwt-r-${_counter++}';
      validTokens.add(jwt);
      return _json(200, {
        'success': true,
        'data': {'jwt': jwt, 'expiresIn': 900},
      });
    }
    final header = options.headers['Authorization'] as String?;
    walletAuthHeaders.add(header);
    final token = header?.startsWith('Bearer ') == true
        ? header!.substring(7)
        : null;
    if (token == null || !validTokens.contains(token)) {
      return _json(401, {'error': 'unauthorized'});
    }
    return _json(200, {'success': true, 'data': <String, dynamic>{}});
  }

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

enum _Prompt { grant, cancel, uiUnavailable }

/// Counts biometric prompts. [_Prompt.uiUnavailable] is what local_auth does
/// when the activity is not a FragmentActivity.
class _CountingLocalAuth implements LocalAuthClient {
  _CountingLocalAuth(this.mode);

  _Prompt mode;
  int prompts = 0;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    prompts++;
    switch (mode) {
      case _Prompt.grant:
        return true;
      case _Prompt.cancel:
        // local_auth 3.x reports a cancel as an exception, not as false.
        throw const LocalAuthException(
          code: LocalAuthExceptionCode.userCanceled,
        );
      case _Prompt.uiUnavailable:
        throw const LocalAuthException(
          code: LocalAuthExceptionCode.uiUnavailable,
        );
    }
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

void main() {
  final vector = jsonDecode(
    File('contract-fixtures/wallet-key-scheme-vector.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  late _Backend backend;
  late InMemoryKeyValueStorage storage;
  late _CountingLocalAuth localAuth;
  late KeyManager keys;
  late AuthHandoffController handoff;
  late String address;

  ApiClient newClient() {
    final authDio = Dio(BaseOptions(baseUrl: 'https://auth.invalid/api'))
      ..httpClientAdapter = backend;
    final client = ApiClient(
      authDio: authDio,
      keyManager: keys,
      authHandoff: handoff,
      ed25519LoginExpectation: const Ed25519LoginExpectation(
        origin: _origin,
        chainId: '777',
        network: 'testnet',
      ),
      loginGuardClock: () => DateTime.utc(2026, 9, 28, 3),
      loginGuardRandom: () => 1.0,
    );
    client.dio.options.baseUrl = 'https://auth.invalid/api';
    client.dio.httpClientAdapter = backend;
    return client;
  }

  /// Wallet creation as CreateWalletScreen stores it.
  Future<void> createWallet() async {
    final wallet = await WalletSetupService().importFromMnemonic(
      vector['mnemonic'] as String,
    );
    address = wallet.address;
    await keys.storeKeys(
      mnemonic: wallet.mnemonic,
      privateKey: wallet.privateKey,
      address: wallet.address,
      keyScheme: wallet.keyScheme,
      loginPrivateKey: wallet.loginPrivateKey,
      loginAddress: wallet.loginAddress,
    );
  }

  /// What the Earnings screen does on open and on pull-to-refresh: an
  /// automatic session check, then the owner-bound wallet request (which
  /// goes through the auth interceptor and its 401 retry).
  Future<void> openEarnings(ApiClient client) async {
    await client.ensureWalletSession();
    try {
      await client.dio.get<dynamic>('/wallet/$address');
    } on DioException {
      // A 401 here is expected when not signed in.
    }
  }

  setUp(() async {
    backend = _Backend();
    storage = InMemoryKeyValueStorage();
    localAuth = _CountingLocalAuth(_Prompt.grant);
    keys = KeyManager(
      biometric: BiometricService(client: localAuth),
      storage: storage,
    );
    handoff = AuthHandoffController();
    LoginAttemptGuard.resetIsolateStateForTest();
    await createWallet();
  });

  test('simultaneous explicit sign-ins keep one slot across the token storage read', () async {
    final client = newClient();
    expect(await Future.wait([client.signInNow(), client.signInNow()]), [
      true,
      true,
    ]);
    expect(backend.nonceGets, 1);
    expect(backend.loginPosts, 1);
    expect(backend.refreshPosts, 0);
    expect(localAuth.prompts, 1);
  });

  test(
    'concurrent explicit sign-ins reuse the completed token without refreshing',
    () async {
      final client = newClient();
      backend.loginGate = Completer<void>();
      final first = client.signInNow();
      for (var i = 0; i < 100 && backend.loginPosts == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(backend.loginPosts, 1);
      final second = client.signInNow();
      await Future<void>.delayed(Duration.zero);
      backend.loginGate!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(backend.loginPosts, 1);
      expect(backend.refreshPosts, 0);
      expect(localAuth.prompts, 1);
    },
  );

  test(
    'creation -> Earnings -> one Sign in -> an authenticated wallet request, '
    'with 1 nonce for the 1 user action',
    () async {
      final client = newClient();

      // Opening Earnings three times is not a user request to sign in.
      for (var i = 0; i < 3; i++) {
        await openEarnings(client);
      }
      expect(localAuth.prompts, 0, reason: 'no automatic biometric prompt');
      expect(backend.nonceGets, 0);
      expect(backend.loginPosts, 0);
      expect(handoff.requiresWalletConnect, isTrue);
      expect(handoff.message, contains('Not signed in'));

      // The user taps Sign in once.
      expect(await client.signInNow(), isTrue);
      expect(localAuth.prompts, 1);
      expect(backend.nonceGets, 1);
      expect(backend.loginPosts, 1);
      expect(handoff.requiresWalletConnect, isFalse);

      final response = await client.dio.get<dynamic>('/wallet/$address');
      expect(response.statusCode, 200);
      final jwt = await keys.getAuthToken();
      expect(backend.walletAuthHeaders.last, 'Bearer $jwt');

      // A second tap while signed in costs nothing.
      expect(await client.signInNow(), isTrue);
      expect(localAuth.prompts, 1);
      expect(backend.nonceGets, 1);
    },
  );

  test('a cancelled prompt: 0 nonce requests and no automatic re-prompt, '
      'including on the 401-retry path', () async {
    localAuth.mode = _Prompt.cancel;
    final client = newClient();

    expect(await client.signInNow(), isFalse);
    expect(localAuth.prompts, 1);
    expect(backend.nonceGets, 0);
    expect(handoff.requiresWalletConnect, isTrue);
    expect(handoff.reason, AuthHandoffReason.notSignedIn);

    // The screen reloads, the user pulls to refresh, a sync runs: each
    // request 401s and the interceptor retries its token once.
    for (var i = 0; i < 5; i++) {
      await openEarnings(client);
    }
    expect(backend.walletAuthHeaders, isNotEmpty);
    expect(localAuth.prompts, 1, reason: 'a cancel is never re-prompted');
    expect(backend.nonceGets, 0);
    expect(backend.loginPosts, 0);

    // Only the next explicit tap prompts again.
    localAuth.mode = _Prompt.grant;
    expect(await client.signInNow(), isTrue);
    expect(localAuth.prompts, 2);
    expect(backend.nonceGets, 1);
  });

  test('a prompt the platform cannot show (no FragmentActivity) says so and '
      'offers Sign in, with no request', () async {
    localAuth.mode = _Prompt.uiUnavailable;
    final client = newClient();

    expect(await client.signInNow(), isFalse);
    expect(backend.nonceGets, 0);
    expect(handoff.requiresWalletConnect, isTrue);
    expect(handoff.reason, AuthHandoffReason.notSignedIn);
    expect(handoff.message, isNotEmpty);

    final promptsAfterTap = localAuth.prompts;
    for (var i = 0; i < 3; i++) {
      await openEarnings(client);
    }
    expect(localAuth.prompts, promptsAfterTap);
    expect(backend.nonceGets, 0);
  });

  test('automatic callers do not overwrite a more specific handoff', () async {
    final client = newClient();
    handoff.requireWalletConnect(
      reason: AuthHandoffReason.sessionExpired,
      message: 'Too many sign-in attempts. Sign-in is paused until 04:00.',
    );

    await openEarnings(client);

    expect(handoff.message, startsWith('Too many sign-in attempts'));
    expect(localAuth.prompts, 0);
    expect(backend.nonceGets, 0);
  });

  test('guard (green on main by design): refresh-token renewal stays automatic '
      'and never prompts', () async {
    await keys.storeAuthSession(
      jwt: 'jwt-expired',
      refreshToken: 'refresh-live',
      expiresInSeconds: -60,
      walletScheme: KeyManager.ed25519AuthScheme,
    );
    final client = newClient();

    expect(await client.ensureWalletSession(), isTrue);
    expect(backend.refreshPosts, 1);
    expect(localAuth.prompts, 0);
    expect(backend.nonceGets, 0);
  });
}
