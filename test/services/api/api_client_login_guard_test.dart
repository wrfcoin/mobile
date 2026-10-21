// mobile#313 / mobile#314: automatic wallet logins are bounded, and only a
// definitive auth rejection wipes the refresh token.
//
// The live backend bans an IP for an hour after 5 logins in 15 minutes, and
// every phone on the tailnet :9444 route can share one limiter bucket
// (mobile#44). These tests drive every automatic trigger that can start a
// login and count the requests that reach the scripted backend.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/auth_handoff_banner.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/ed25519_wallet_login.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/fake_station_backend.dart';

import '../../test_helpers/fakes.dart';

const _origin = 'https://wallet.test';

enum _Mode { ok, reject, offline, rateLimited, serverError }

/// Scripted backend: counts auth requests, answers per [_Mode].
class _ScriptedBackend implements HttpClientAdapter {
  _Mode nonce = _Mode.ok;
  _Mode login = _Mode.ok;
  _Mode refresh = _Mode.ok;

  /// When true every protected route answers 401 even with a fresh token.
  bool protectedAlways401 = false;

  /// Scripted answers for the next protected calls, consumed in order
  /// (after it is empty, the normal token check applies).
  final List<_Mode> protectedQueue = <_Mode>[];

  int nonceGets = 0;
  int loginPosts = 0;
  int refreshPosts = 0;
  int protectedCalls = 0;
  final Set<String> validTokens = <String>{};
  int _counter = 0;

  static String message(String address, String nonce) {
    final now = DateTime.now().toUtc();
    return 'wrfcoin_wallet_login_ed25519_v1\n'
        '${Uri.parse(_origin).host} wants you to sign in with your WRFCoin ed25519 account:\n'
        '$address\n\nSign in to WRFCoin Testnet.\n\n'
        'URI: $_origin\nVersion: 1\nScheme: ed25519\nChain ID: 777\n'
        'Network: testnet\nNonce: $nonce\n'
        'Issued At: ${now.toIso8601String()}\n'
        'Expiration Time: ${now.add(const Duration(minutes: 5)).toIso8601String()}';
  }

  Never _offline(RequestOptions o) => throw DioException.connectionError(
    requestOptions: o,
    reason: 'offline (test)',
  );

  ResponseBody? _failure(_Mode mode, RequestOptions o) {
    switch (mode) {
      case _Mode.ok:
        return null;
      case _Mode.reject:
        return _json(401, {'success': false, 'error': 'rejected (test)'});
      case _Mode.offline:
        _offline(o);
      case _Mode.rateLimited:
        return _json(
          429,
          {'error': 'too many'},
          extra: {
            'retry-after': ['3600'],
          },
        );
      case _Mode.serverError:
        return _json(503, {'error': 'unavailable'});
    }
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
      final failed = _failure(nonce, options);
      if (failed != null) return failed;
      final address = path.split('/').last;
      final n = 'n-${_counter++}';
      return _json(200, {
        'success': true,
        'data': {
          'nonce': n,
          'message': message(address, n),
          'scheme': 'ed25519',
        },
      });
    }
    if (options.method == 'POST' && path.endsWith('/auth/wallet-login')) {
      loginPosts++;
      final failed = _failure(login, options);
      if (failed != null) return failed;
      final jwt = 'jwt-${_counter++}';
      validTokens.add(jwt);
      return _json(200, {
        'success': true,
        'data': {'jwt': jwt, 'refreshToken': 'refresh-$jwt', 'expiresIn': 900},
      });
    }
    if (options.method == 'POST' && path.endsWith('/auth/refresh')) {
      refreshPosts++;
      final failed = _failure(refresh, options);
      if (failed != null) return failed;
      final jwt = 'jwt-r-${_counter++}';
      validTokens.add(jwt);
      return _json(200, {
        'success': true,
        'data': {'jwt': jwt, 'expiresIn': 900},
      });
    }
    protectedCalls++;
    if (protectedQueue.isNotEmpty) {
      final mode = protectedQueue.removeAt(0);
      final failed = _failure(mode, options);
      if (failed != null) return failed;
    }
    final header = options.headers['Authorization'] as String?;
    final token = header?.startsWith('Bearer ') == true
        ? header!.substring(7)
        : null;
    if (protectedAlways401 || token == null || !validTokens.contains(token)) {
      return _json(401, {'error': 'unauthorized'});
    }
    if (path.endsWith('/oracle/submit-data')) {
      return _json(200, {
        'success': true,
        'submissionId': 's-1',
        'status': 'accepted',
      });
    }
    return _json(200, {'success': true, 'data': <String, dynamic>{}});
  }

  static ResponseBody _json(
    int status,
    Object body, {
    Map<String, List<String>> extra = const {},
  }) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...extra,
    },
  );
}

/// A manually advanced clock shared by guards in one test.
class _Clock {
  DateTime now = DateTime.utc(2026, 9, 27, 3, 0);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  final vector = jsonDecode(
    File('contract-fixtures/wallet-key-scheme-vector.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  late _ScriptedBackend backend;
  late InMemoryKeyValueStorage storage;
  late KeyManager keys;
  late AuthHandoffController handoff;
  late _Clock clock;

  KeyManager newKeyManager() => KeyManager(
    biometric: BiometricService(
      client: FakeLocalAuthClient(authenticateResult: true),
    ),
    storage: storage,
  );

  /// A client wired like production: auth interceptor on [ApiClient.dio],
  /// a separate auth Dio, and the guard persisted in the key storage.
  ApiClient newClient({
    KeyManager? keyManager,
    AuthHandoffController? auth,
    bool canStartLogin = true,
  }) {
    final authDio = Dio(BaseOptions(baseUrl: 'https://auth.invalid/api'))
      ..httpClientAdapter = backend;
    final client = ApiClient(
      authDio: authDio,
      keyManager: keyManager ?? keys,
      authHandoff: auth,
      ed25519LoginExpectation: const Ed25519LoginExpectation(
        origin: _origin,
        chainId: '777',
        network: 'testnet',
      ),
      loginGuardClock: clock.call,
      loginGuardRandom: () => 1.0,
      canStartLogin: canStartLogin,
    );
    client.dio.options.baseUrl = 'https://auth.invalid/api';
    client.dio.httpClientAdapter = backend;
    return client;
  }

  Future<void> storeVectorWallet() async {
    final wallet = await WalletSetupService().importFromMnemonic(
      vector['mnemonic'] as String,
    );
    await keys.storeKeys(
      mnemonic: wallet.mnemonic,
      privateKey: wallet.privateKey,
      address: wallet.address,
      keyScheme: wallet.keyScheme,
      loginPrivateKey: wallet.loginPrivateKey,
      loginAddress: wallet.loginAddress,
    );
  }

  /// A session whose access token has expired but whose refresh token is
  /// still good, as after 15 minutes in the background.
  Future<void> storeExpiredSession() => keys.storeAuthSession(
    jwt: 'jwt-expired',
    refreshToken: 'refresh-live',
    expiresInSeconds: -60,
    walletScheme: KeyManager.ed25519AuthScheme,
  );

  setUp(() async {
    backend = _ScriptedBackend();
    storage = InMemoryKeyValueStorage();
    keys = newKeyManager();
    handoff = AuthHandoffController();
    clock = _Clock();
    LoginAttemptGuard.resetIsolateStateForTest();
    await storeVectorWallet();
  });

  // mobile#320: automatic callers never start a wallet login (it would need
  // a biometric prompt), so each group starts its login with the explicit
  // Sign in and then drives the automatic triggers that used to retry it.
  group('mobile#313: a rejected login is not retried automatically', () {
    test('a rejected Sign in is not retried by ensureWalletSession (collector sync, wallet screen)', () async {
      backend.login = _Mode.reject;
      final client = newClient(auth: handoff);
      expect(await client.signInNow(), isFalse);

      for (var i = 0; i < 8; i++) {
        expect(await client.ensureWalletSession(), isFalse);
      }

      expect(backend.loginPosts, 1);
      expect(backend.nonceGets, 1);
      expect(handoff.requiresWalletConnect, isTrue);
    });

    test('the auth interceptor does not start a login per request after a rejection', () async {
      backend.login = _Mode.reject;
      final client = newClient(auth: handoff);
      expect(await client.signInNow(), isFalse);

      for (var i = 0; i < 8; i++) {
        await expectLater(
          client.dio.get<dynamic>('/weather/current'),
          throwsA(isA<DioException>()),
        );
      }

      expect(backend.loginPosts, 1);
    });

    test('the 401-retry path cannot loop logins when the server keeps answering 401', () async {
      backend.protectedAlways401 = true;
      final client = newClient(auth: handoff);
      expect(await client.signInNow(), isTrue);

      for (var i = 0; i < 8; i++) {
        await expectLater(
          client.dio.get<dynamic>('/wallet/0xabc'),
          throwsA(isA<DioException>()),
        );
      }

      // One login, one refresh-backed retry, then a hold: no second login
      // even long after the window, until the user signs in.
      expect(backend.loginPosts, 1);
      clock.advance(const Duration(hours: 2));
      handoff.clear();
      await expectLater(
        client.dio.get<dynamic>('/wallet/0xabc'),
        throwsA(isA<DioException>()),
      );
      expect(backend.loginPosts, 1);
      expect(handoff.requiresWalletConnect, isTrue);
    });

    test(
      'collector submitBatch does not log in per sync after a rejection',
      () async {
        backend.login = _Mode.reject;
        final client = newClient(auth: handoff);
        expect(await client.signInNow(), isFalse);
        final repository = CollectorRepository(
          sensorDataSource: SensorDataSource(LocationService()),
          batteryMonitor: BatteryMonitor(),
          apiClient: client,
          db: FakeCollectorLocalStore()..pendingCount = 1,
        );
        final session = await syntheticCollectKey();
        final reading = SensorReading(
          id: 1,
          latitude: 1,
          longitude: 2,
          pressureHpa: 1000,
          timestamp: DateTime.utc(2026, 9, 27),
          synced: false,
        );

        for (var i = 0; i < 6; i++) {
          final result = await repository.submitBatch(
            [reading],
            walletAddress: 'mobile',
            signer: session,
          );
          expect(result.acceptedCount, 0);
        }

        expect(backend.loginPosts, 1);
      },
    );

    test(
      'walletProvider rebuilds do not log in again after a rejection',
      () async {
        backend.login = _Mode.reject;
        final client = newClient(auth: handoff);
        expect(await client.signInNow(), isFalse);
        final container = ProviderContainer(
          overrides: [
            keyManagerProvider.overrideWithValue(keys),
            apiClientProvider.overrideWithValue(client),
            authHandoffControllerProvider.overrideWith((ref) => handoff),
          ],
        );
        addTearDown(container.dispose);

        for (var i = 0; i < 5; i++) {
          container.invalidate(walletProvider);
          await container.read(walletProvider.future).catchError((_) => null);
        }

        expect(backend.loginPosts, 1);
      },
    );

    test('a background-isolate client (sensor/sync worker) shares the persisted guard', () async {
      backend.login = _Mode.reject;
      final foreground = newClient(auth: handoff);
      expect(await foreground.signInNow(), isFalse);

      // sensor_worker / sync_worker build their own ApiClient + KeyManager
      // over the same secure storage, with no AuthHandoffController.
      final background = newClient(keyManager: newKeyManager());
      for (var i = 0; i < 5; i++) {
        expect(await background.ensureWalletSession(), isFalse);
      }

      expect(backend.loginPosts, 1);
    });
  });

  group('mobile#313: offline and server failures back off', () {
    test('offline: repeated syncs do not hammer the nonce endpoint', () async {
      backend.nonce = _Mode.offline;
      final client = newClient(auth: handoff);
      expect(await client.signInNow(), isFalse);

      for (var i = 0; i < 6; i++) {
        expect(await client.ensureWalletSession(), isFalse);
      }

      expect(backend.nonceGets, 1);
      // A transport failure is not a rejection: the handoff only says that
      // nobody is signed in.
      expect(handoff.message, startsWith('Not signed in'));
    });

    test('the backoff is exponential, jittered and capped', () {
      Duration at(int failures, double r) =>
          LoginAttemptGuard.backoffFor(failures, random: () => r);
      expect(at(1, 1.0), LoginAttemptGuard.baseBackoff);
      expect(at(2, 1.0), LoginAttemptGuard.baseBackoff * 2);
      expect(at(3, 1.0), LoginAttemptGuard.baseBackoff * 4);
      expect(at(30, 1.0), LoginAttemptGuard.maxBackoff);
      // Jitter spans [50%, 100%] of the step.
      expect(at(2, 0.0), LoginAttemptGuard.baseBackoff);
      expect(at(30, 0.0), LoginAttemptGuard.maxBackoff * 0.5);
    });

    test('an offline Sign in is not retried automatically, even after the backoff; the next Sign in works', () async {
      backend.nonce = _Mode.offline;
      final client = newClient(auth: handoff);
      expect(await client.signInNow(), isFalse);
      expect(backend.nonceGets, 1);

      backend.nonce = _Mode.ok;
      clock.advance(LoginAttemptGuard.baseBackoff + const Duration(seconds: 1));
      expect(await client.ensureWalletSession(), isFalse);
      expect(backend.nonceGets, 1, reason: 'automatic callers never retry');

      expect(await client.signInNow(), isTrue);
      expect(backend.nonceGets, 2);
      expect(backend.loginPosts, 1);
    });

    test('a 429 on login locks automatic and manual sign-in for the Retry-After window', () async {
      backend.login = _Mode.rateLimited;
      final client = newClient(auth: handoff);
      expect(await client.signInNow(), isFalse);
      expect(await client.ensureWalletSession(), isFalse);
      expect(await client.signInNow(), isFalse);
      clock.advance(const Duration(minutes: 59));
      expect(await client.signInNow(), isFalse);

      expect(backend.loginPosts, 1);
      expect(handoff.requiresWalletConnect, isTrue);
    });
  });

  group('mobile#313: hard ceiling, then an explicit user action', () {
    test(
      'no automatic login at all, even when the session keeps being revoked',
      () async {
        final client = newClient(auth: handoff);
        expect(await client.signInNow(), isTrue);
        for (var i = 0; i < 5; i++) {
          await keys.clearAuthSession(); // e.g. the server revoked the session
          await client.ensureWalletSession();
          clock.advance(const Duration(minutes: 1));
        }

        expect(backend.loginPosts, 1);
        expect(handoff.requiresWalletConnect, isTrue);
      },
    );

    test('without a session, automatic callers wait for Sign in, not merely until the window passes', () async {
      final client = newClient(auth: handoff);
      expect(await client.signInNow(), isTrue);
      for (var i = 0; i < 3; i++) {
        await keys.clearAuthSession();
        await client.ensureWalletSession();
      }
      expect(backend.loginPosts, 1);

      clock.advance(const Duration(hours: 2));
      await keys.clearAuthSession();
      expect(await client.ensureWalletSession(), isFalse);
      expect(backend.loginPosts, 1);

      expect(await client.signInNow(), isTrue);
      expect(backend.loginPosts, 2);
      expect(handoff.requiresWalletConnect, isFalse);
    });

    test('an honoured wallet-connect handoff blocks automatic logins until the user acts', () async {
      backend.login = _Mode.reject;
      final client = newClient(auth: handoff);
      expect(await client.signInNow(), isFalse);
      expect(handoff.requiresWalletConnect, isTrue);

      backend.login = _Mode.ok;
      handoff.clear(); // "Dismiss" on the banner is not a sign-in.
      clock.advance(const Duration(hours: 3));
      expect(await client.ensureWalletSession(), isFalse);
      expect(backend.loginPosts, 1);

      expect(await client.signInNow(), isTrue);
      expect(await client.ensureWalletSession(), isTrue);
      expect(backend.loginPosts, 2);
    });

    test('manual sign-in is capped too: at most 4 logins of any kind per 15 minutes', () async {
      backend.login = _Mode.reject;
      final client = newClient(auth: handoff);
      for (var i = 0; i < 8; i++) {
        await client.signInNow();
      }

      expect(backend.loginPosts, LoginAttemptGuard.maxAttemptsPerWindow);
      expect(LoginAttemptGuard.maxAttemptsPerWindow, lessThan(5));
    });

    test(
      'storing a new wallet does not log in by itself; its Sign in does',
      () async {
        backend.login = _Mode.reject;
        final client = newClient(auth: handoff);
        expect(await client.signInNow(), isFalse);

        backend.login = _Mode.ok;
        clock.advance(const Duration(minutes: 20));
        await storeVectorWallet();
        expect(await client.ensureWalletSession(), isFalse);
        expect(backend.loginPosts, 1);
        expect(await client.signInNow(), isTrue);
        expect(backend.loginPosts, 2);
      },
    );

    test('unreadable guard state fails closed for automatic logins', () async {
      await storage.write(
        key: LoginAttemptGuard.storageKey,
        value: '{not json',
      );
      final client = newClient(auth: handoff);

      expect(await client.ensureWalletSession(), isFalse);
      expect(backend.nonceGets, 0);
    });
  });

  group('mobile#314: only a definitive rejection wipes the refresh token', () {
    test('an expired access token keeps the refresh token and refreshes without a login', () async {
      await storeExpiredSession();
      final client = newClient(auth: handoff);

      expect(await client.ensureWalletSession(), isTrue);
      expect(backend.refreshPosts, 1);
      expect(backend.loginPosts, 0);
      expect(backend.nonceGets, 0);
    });

    test('offline refresh keeps the refresh token and does not fall through to a login', () async {
      await storeExpiredSession();
      backend.refresh = _Mode.offline;
      final client = newClient(auth: handoff);

      expect(await client.ensureWalletSession(), isFalse);
      expect(await keys.getRefreshToken(), 'refresh-live');
      expect(backend.nonceGets, 0);
      expect(backend.loginPosts, 0);

      // Back online: a silent refresh, still no login.
      backend.refresh = _Mode.ok;
      expect(await client.ensureWalletSession(), isTrue);
      expect(backend.loginPosts, 0);
    });

    test('a 5xx from refresh keeps the refresh token', () async {
      await storeExpiredSession();
      backend.refresh = _Mode.serverError;
      final client = newClient(auth: handoff);

      expect(await client.ensureWalletSession(), isFalse);
      expect(await keys.getRefreshToken(), 'refresh-live');
      expect(backend.loginPosts, 0);
    });

    test('a 429 from refresh keeps the refresh token', () async {
      await storeExpiredSession();
      backend.refresh = _Mode.rateLimited;
      final client = newClient(auth: handoff);

      expect(await client.ensureWalletSession(), isFalse);
      expect(await keys.getRefreshToken(), 'refresh-live');
      expect(backend.loginPosts, 0);
    });

    test(
      'a 401 from refresh wipes the session and waits for Sign in',
      () async {
        await storeExpiredSession();
        backend.refresh = _Mode.reject;
        final client = newClient(auth: handoff);

        expect(await client.ensureWalletSession(), isFalse);
        expect(backend.refreshPosts, 1);
        expect(backend.loginPosts, 0);
        expect(await keys.getRefreshToken(), isNull);
        expect(handoff.message, startsWith('Not signed in'));

        expect(await client.signInNow(), isTrue);
        expect(backend.loginPosts, 1);
      },
    );
  });

  group('codex round 48 [P1] the interceptor keeps transient failures transient', () {
    test('expired access token + offline refresh + protected 401: the refresh token survives, no login, no hold', () async {
      await storeExpiredSession();
      backend.refresh = _Mode.offline;
      final client = newClient(auth: handoff);

      await expectLater(
        client.dio.get<dynamic>('/wallet/0xabc'),
        throwsA(isA<DioException>()),
      );

      expect(await keys.getRefreshToken(), 'refresh-live');
      expect(backend.loginPosts, 0);
      expect(backend.nonceGets, 0);
      expect(handoff.requiresWalletConnect, isFalse);

      // Back online: a silent refresh restores the session, no login.
      backend.refresh = _Mode.ok;
      expect(await client.ensureWalletSession(), isTrue);
      expect(backend.loginPosts, 0);
    });

    test(
      'a 401 whose retry fails offline keeps the session and sets no hold',
      () async {
        final client = newClient(auth: handoff);
        expect(await client.signInNow(), isTrue); // one login
        final refreshBefore = await keys.getRefreshToken();
        expect(refreshBefore, isNotNull);

        // Stale token -> 401, then the retry with a refreshed token is offline.
        backend.protectedQueue.addAll([_Mode.reject, _Mode.offline]);
        await expectLater(
          client.dio.get<dynamic>('/wallet/0xabc'),
          throwsA(isA<DioException>()),
        );

        expect(await keys.getRefreshToken(), isNotNull);
        expect(handoff.requiresWalletConnect, isFalse);
        expect(backend.loginPosts, 1);

        // Nothing is held: the next request works without a new login.
        expect(
          (await client.dio.get<dynamic>('/wallet/0xabc')).statusCode,
          200,
        );
        expect(backend.loginPosts, 1);
      },
    );

    test('a 401 whose retry gets a 5xx keeps the session', () async {
      final client = newClient(auth: handoff);
      expect(await client.signInNow(), isTrue);

      // _RetryInterceptor re-tries a 5xx twice, so every try must fail.
      backend.protectedQueue.addAll([
        _Mode.reject,
        _Mode.serverError,
        _Mode.serverError,
        _Mode.serverError,
      ]);
      await expectLater(
        client.dio.get<dynamic>('/wallet/0xabc'),
        throwsA(isA<DioException>()),
      );

      expect(await keys.getRefreshToken(), isNotNull);
      expect(handoff.requiresWalletConnect, isFalse);
    });
  });

  // mobile#320: ApiClient no longer asks for automatic permits, so the
  // automatic ceiling is pinned on the guard itself.
  group('codex round 48 [P2] the automatic ceiling latches on the second permit', () {
    LoginAttemptGuard guardOver(Map<String, String?> store) =>
        LoginAttemptGuard(
          read: () async => store['g'],
          write: (v) async => store['g'] = v,
          clock: clock.call,
          random: () => 1.0,
        );

    test('two failed automatic permits, then a new guard after the window: no third', () async {
      final store = <String, String?>{};
      final guard = guardOver(store);
      expect((await guard.requestPermit(userInitiated: false)).allowed, isTrue);
      await guard.recordOutcome(LoginOutcome.transientFailure); // t=0
      clock.advance(const Duration(minutes: 3));
      expect((await guard.requestPermit(userInitiated: false)).allowed, isTrue);
      await guard.recordOutcome(LoginOutcome.transientFailure); // t=3

      clock.advance(const Duration(minutes: 20)); // t=23, window expired
      final restarted = guardOver(store);
      expect(
        (await restarted.requestPermit(userInitiated: false)).allowed,
        isFalse,
      );
      expect(
        (await restarted.requestPermit(userInitiated: true)).allowed,
        isTrue,
      );
    });

    test(
      'a successful second automatic permit does not release the ceiling hold',
      () async {
        final store = <String, String?>{};
        final guard = guardOver(store);
        expect(
          (await guard.requestPermit(userInitiated: false)).allowed,
          isTrue,
        );
        await guard.recordOutcome(LoginOutcome.success);
        expect(
          (await guard.requestPermit(userInitiated: false)).allowed,
          isTrue,
        );
        await guard.recordOutcome(LoginOutcome.success);

        clock.advance(const Duration(hours: 1));
        expect(
          (await guard.requestPermit(userInitiated: false)).allowed,
          isFalse,
        );
      },
    );
  });

  group(
    'codex round 48 [P1] overlapping clients cannot exceed the ceiling',
    () {
      test('two clients over the same storage, overlapping at t=0 and after backoff: at most 2 logins', () async {
        backend.login = _Mode.serverError;
        final a = newClient(auth: handoff);
        final b = newClient(keyManager: newKeyManager());

        await Future.wait([a.ensureWalletSession(), b.ensureWalletSession()]);
        clock.advance(const Duration(minutes: 5));
        await Future.wait([a.ensureWalletSession(), b.ensureWalletSession()]);
        clock.advance(const Duration(minutes: 5));
        await Future.wait([a.ensureWalletSession(), b.ensureWalletSession()]);

        expect(
          backend.loginPosts,
          lessThanOrEqualTo(LoginAttemptGuard.maxAutomaticAttemptsPerWindow),
        );
      });

      test(
        'concurrent permits on two guard instances never lose an attempt',
        () async {
          final store = <String, String?>{};
          Future<String?> read() async {
            await Future<void>.delayed(Duration.zero);
            return store['g'];
          }

          Future<void> write(String v) async {
            await Future<void>.delayed(Duration.zero);
            store['g'] = v;
          }

          LoginAttemptGuard guard() => LoginAttemptGuard(
            read: read,
            write: write,
            clock: clock.call,
            random: () => 1.0,
          );
          final g1 = guard();
          final g2 = guard();

          final permits = await Future.wait([
            g1.requestPermit(userInitiated: false),
            g2.requestPermit(userInitiated: false),
            g1.requestPermit(userInitiated: false),
            g2.requestPermit(userInitiated: false),
          ]);

          expect(
            permits.where((p) => p.allowed).length,
            LoginAttemptGuard.maxAutomaticAttemptsPerWindow,
          );
          expect(
            LoginGuardState.decode(store['g']).attempts.length,
            LoginAttemptGuard.maxAutomaticAttemptsPerWindow,
          );
        },
      );

      test('a concurrent transient outcome cannot erase a 429 lock', () async {
        final store = <String, String?>{};
        Future<String?> read() async {
          await Future<void>.delayed(Duration.zero);
          return store['g'];
        }

        Future<void> write(String v) async {
          await Future<void>.delayed(Duration.zero);
          store['g'] = v;
        }

        final g1 = LoginAttemptGuard(
          read: read,
          write: write,
          clock: clock.call,
        );
        final g2 = LoginAttemptGuard(
          read: read,
          write: write,
          clock: clock.call,
        );

        await Future.wait([
          g1.recordOutcome(
            LoginOutcome.rateLimited,
            retryAfter: const Duration(hours: 1),
          ),
          g2.recordOutcome(LoginOutcome.transientFailure),
        ]);

        final state = LoginGuardState.decode(store['g']);
        expect(state.rateLimitedUntil, isNotNull);
        expect(state.consecutiveFailures, 1);
        expect(
          (await g1.requestPermit(userInitiated: true)).status,
          LoginPermitStatus.rateLimited,
        );
      });

      test('a manual sign-in overlapping an automatic one keeps the 429 lock and counters', () async {
        backend.login = _Mode.rateLimited;
        final ui = newClient(auth: handoff);
        final sync = newClient(keyManager: newKeyManager());

        final results = await Future.wait([
          sync.ensureWalletSession(),
          ui.signInNow(),
        ]);

        expect(results, [isFalse, isFalse]);
        expect(
          backend.loginPosts,
          1,
          reason: 'the 429 locks the second attempt',
        );
        final state = LoginGuardState.decode(
          await storage.read(key: LoginAttemptGuard.storageKey),
        );
        expect(state.rateLimitedUntil, isNotNull);
        expect(state.attempts.length, 1);
        clock.advance(const Duration(minutes: 30));
        expect(await ui.signInNow(), isFalse);
        expect(backend.loginPosts, 1);
      });

      test(
        'a Workmanager-isolate client never starts a login, but may refresh',
        () async {
          final background = newClient(
            keyManager: newKeyManager(),
            canStartLogin: false,
          );
          expect(await background.ensureWalletSession(), isFalse);
          expect(await background.signInNow(), isFalse);
          expect(backend.nonceGets, 0);
          // Only setUp's wallet import (the release) has written the guard.
          expect(
            LoginGuardState.decode(
              await storage.read(key: LoginAttemptGuard.storageKey),
            ).attempts,
            isEmpty,
          );

          await storeExpiredSession();
          expect(await background.ensureWalletSession(), isTrue);
          expect(backend.refreshPosts, 1);
          expect(backend.loginPosts, 0);
        },
      );
    },
  );

  test('a later, shorter 429 never shortens an existing lock', () async {
    final store = <String, String?>{};
    final g = LoginAttemptGuard(
      read: () async => store['g'],
      write: (v) async => store['g'] = v,
      clock: clock.call,
    );
    await g.recordOutcome(
      LoginOutcome.rateLimited,
      retryAfter: const Duration(hours: 2),
    );
    await g.recordOutcome(LoginOutcome.rateLimited);
    clock.advance(const Duration(minutes: 90));
    expect(
      (await g.requestPermit(userInitiated: true)).status,
      LoginPermitStatus.rateLimited,
    );
  });

  group('codex round 48 [P2] Emergency Wipe cannot drop the login guard', () {
    test('the guard lives in its own storage: a wipe (even with failing reads) keeps a 429 lock', () async {
      final walletStore = _FlakyStorage();
      final guardStore = _FlakyStorage();
      KeyManager km() => KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(authenticateResult: true),
        ),
        storage: walletStore,
        loginGuardStorage: guardStore,
      );
      keys = km();
      await storeVectorWallet();
      backend.login = _Mode.rateLimited;
      final client = newClient(keyManager: keys, auth: handoff);
      expect(await client.signInNow(), isFalse);
      expect(backend.loginPosts, 1);

      walletStore.failReads = true;
      guardStore.failReads = true;
      await keys.deleteAll(); // Emergency Wipe
      walletStore.failReads = false;
      guardStore.failReads = false;

      expect(await keys.hasWallet(), isFalse);
      expect(
        await guardStore.read(key: LoginAttemptGuard.storageKey),
        isNotNull,
      );

      await storeVectorWallet(); // re-import
      backend.login = _Mode.ok;
      final after = newClient(keyManager: km(), auth: handoff);
      expect(await after.ensureWalletSession(), isFalse);
      expect(await after.signInNow(), isFalse);
      expect(backend.loginPosts, 1);
    });

    test('a guard write failure refuses the login', () async {
      final guardStore = _FlakyStorage()..failWrites = true;
      keys = KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(authenticateResult: true),
        ),
        storage: storage,
        loginGuardStorage: guardStore,
      );
      final client = newClient(keyManager: keys, auth: handoff);
      expect(await client.signInNow(), isFalse);
      expect(backend.nonceGets, 0);
    });
  });

  group('codex round 54: "Sign in again" recovers a corrupt guard', () {
    late _FlakyStorage guardStore;

    ApiClient clientWithGuardStore() {
      keys = KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(authenticateResult: true),
        ),
        storage: storage,
        loginGuardStorage: guardStore,
      );
      return newClient(keyManager: keys, auth: handoff);
    }

    Future<void> corrupt([String raw = '{not json']) =>
        guardStore.write(key: LoginAttemptGuard.storageKey, value: raw);

    setUp(() => guardStore = _FlakyStorage());

    test('automatic refusal, then a manual sign-in rewrites the guard and logs in (no re-import)', () async {
      final client = clientWithGuardStore();
      await corrupt();

      expect(await client.ensureWalletSession(), isFalse);
      expect(backend.nonceGets, 0, reason: 'automatic paths stay fail-closed');
      expect(handoff.requiresWalletConnect, isTrue);

      expect(await client.signInNow(), isTrue);
      expect(backend.loginPosts, 1);
      expect(handoff.requiresWalletConnect, isFalse);
      // The rewritten guard is well-formed and records the attempt.
      final state = LoginGuardState.decode(
        await guardStore.read(key: LoginAttemptGuard.storageKey),
      );
      expect(state.attempts, hasLength(1));
      expect(await client.ensureWalletSession(), isTrue);
    });

    testWidgets('the "Sign in again" button recovers through the real client', (
      tester,
    ) async {
      final client = clientWithGuardStore();
      await tester.runAsync(() async {
        await corrupt();
        expect(await client.ensureWalletSession(), isFalse);
      });
      expect(handoff.requiresWalletConnect, isTrue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: handoff,
                builder: (_, _) => AuthHandoffBanner(handoff: handoff),
              ),
            ),
          ),
        ),
      );
      // Tap and let the real (non-fake-async) HTTP round trip complete.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('auth-handoff-sign-in')));
        for (var i = 0; i < 50 && backend.loginPosts == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(backend.loginPosts, 1);
      expect(handoff.requiresWalletConnect, isFalse);
      expect(find.text('Sign in again'), findsNothing);
    });

    test('a readable 429 lock survives recovery', () async {
      final client = clientWithGuardStore();
      final until = clock.now.add(const Duration(minutes: 40));
      await corrupt(
        '{"attempts":"garbage","rateLimitedUntil":${until.millisecondsSinceEpoch}}',
      );

      expect(await client.signInNow(), isFalse);
      expect(backend.nonceGets, 0);
      expect(handoff.message, contains('Too many sign-in attempts'));
    });

    test('a readable window cap survives recovery', () async {
      final client = clientWithGuardStore();
      final t = clock.now.millisecondsSinceEpoch;
      await corrupt('{"attempts":[$t,$t,$t,$t],"consecutiveFailures":"bad"}');

      expect(await client.signInNow(), isFalse);
      expect(backend.nonceGets, 0);
    });

    test(
      'recovery fails, before any request, when the rewrite cannot be stored',
      () async {
        final client = clientWithGuardStore();
        await corrupt();
        guardStore.failWrites = true;

        expect(await client.signInNow(), isFalse);
        expect(backend.nonceGets, 0);
        expect(handoff.message, contains('secure storage'));
      },
    );

    test(
      'recovery fails when the rewrite does not persist (read-back check)',
      () async {
        final client = clientWithGuardStore();
        await corrupt();
        guardStore.dropWrites = true;

        expect(await client.signInNow(), isFalse);
        expect(backend.nonceGets, 0);
        expect(handoff.message, contains('secure storage'));
      },
    );

    test(
      'a guard that cannot be read at all gives an actionable storage error',
      () async {
        final client = clientWithGuardStore();
        guardStore.failReads = true;

        expect(await client.ensureWalletSession(), isFalse);
        expect(await client.signInNow(), isFalse);
        expect(backend.nonceGets, 0);
        expect(handoff.message, contains('secure storage'));
      },
    );

    test(
      'the manual cap still holds when the guard keeps getting corrupted',
      () async {
        backend.login = _Mode.reject;
        final client = clientWithGuardStore();
        for (var i = 0; i < 7; i++) {
          await corrupt();
          await client.signInNow();
        }

        expect(backend.loginPosts, LoginAttemptGuard.maxAttemptsPerWindow);
      },
    );

    test('after recovery the ordinary manual cap applies', () async {
      backend.login = _Mode.reject;
      final client = clientWithGuardStore();
      await corrupt();
      for (var i = 0; i < 7; i++) {
        await client.signInNow();
      }

      expect(backend.loginPosts, LoginAttemptGuard.maxAttemptsPerWindow);
    });
  });

  group(
    'codex round 57: durability, total-cap accounting, malformed fields',
    () {
      late _FlakyStorage guardStore;

      ApiClient clientWithGuardStore() {
        keys = KeyManager(
          biometric: BiometricService(
            client: FakeLocalAuthClient(authenticateResult: true),
          ),
          storage: storage,
          loginGuardStorage: guardStore,
        );
        return newClient(keyManager: keys, auth: handoff);
      }

      Future<void> setRaw(String raw) =>
          guardStore.write(key: LoginAttemptGuard.storageKey, value: raw);

      int lockMs() =>
          clock.now.add(const Duration(minutes: 40)).millisecondsSinceEpoch;

      setUp(() => guardStore = _FlakyStorage());

      test('[P1] a readable ledger on a store that drops writes: manual sign-in is refused before any request', () async {
        final client = clientWithGuardStore();
        await setRaw(LoginGuardState(userActionRequired: true).encode());
        guardStore.dropWrites = true;

        expect(await client.signInNow(), isFalse);
        expect(backend.nonceGets, 0);
        expect(handoff.message, contains('secure storage'));
      });

      test('[P1] a readable ledger on a store that drops writes: automatic login is refused', () async {
        final client = clientWithGuardStore();
        await setRaw(LoginGuardState().encode());
        guardStore.dropWrites = true;

        expect(await client.ensureWalletSession(), isFalse);
        expect(backend.nonceGets, 0);
      });

      test('[P1] two sign-ins, then corruption before each further sign-in: at most 4 logins in the window', () async {
        backend.login = _Mode.serverError;
        final client = clientWithGuardStore();
        expect(await client.signInNow(), isFalse); // t=0
        clock.advance(const Duration(minutes: 3));
        expect(await client.signInNow(), isFalse); // t=3
        expect(backend.loginPosts, 2);

        for (var i = 0; i < 6; i++) {
          await setRaw('{not json');
          await client.signInNow();
        }

        expect(backend.loginPosts, LoginAttemptGuard.maxAttemptsPerWindow);
      });

      test('[P1] a 429 lock survives the stored ledger being corrupted in the same session', () async {
        backend.login = _Mode.rateLimited;
        final client = clientWithGuardStore();
        expect(await client.signInNow(), isFalse);
        expect(backend.loginPosts, 1);

        await setRaw('{not json');
        backend.login = _Mode.ok;
        expect(await client.signInNow(), isFalse);
        expect(backend.loginPosts, 1);
      });

      test('[P2] an out-of-range timestamp does not throw and keeps a readable 429 lock', () async {
        final raw =
            '{"attempts":[8640000000000001],"rateLimitedUntil":${lockMs()}}';
        expect(() => LoginGuardState.salvage(raw), returnsNormally);
        expect(LoginGuardState.salvage(raw).rateLimitedUntil, isNotNull);

        final client = clientWithGuardStore();
        await setRaw(raw);
        expect(await client.signInNow(), isFalse);
        expect(backend.nonceGets, 0);
        expect(handoff.message, contains('Too many sign-in attempts'));
      });

      testWidgets(
        '[P2] the button survives an out-of-range timestamp and stays usable',
        (tester) async {
          final client = clientWithGuardStore();
          await tester.runAsync(() async {
            await setRaw(
              '{"attempts":[8640000000000001],"rateLimitedUntil":${lockMs()}}',
            );
            handoff.requireWalletConnect(
              reason: AuthHandoffReason.sessionExpired,
              message: 'Automatic sign-in is paused.',
            );
          });
          await tester.pumpWidget(
            ProviderScope(
              overrides: [apiClientProvider.overrideWithValue(client)],
              child: MaterialApp(
                home: Scaffold(
                  body: ListenableBuilder(
                    listenable: handoff,
                    builder: (_, _) => AuthHandoffBanner(handoff: handoff),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            await tester.tap(find.byKey(const Key('auth-handoff-sign-in')));
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(backend.nonceGets, 0);
          final button = tester.widget<TextButton>(
            find.byKey(const Key('auth-handoff-sign-in')),
          );
          expect(button.onPressed, isNotNull, reason: 'busy state was reset');
        },
      );

      test('self-review: a guard-storage write failure does not fail a wallet import', () async {
        final client = clientWithGuardStore();
        guardStore.failWrites = true;
        await storeVectorWallet(); // must not throw
        expect(await keys.hasWallet(), isTrue);
        guardStore.failWrites = false;
        expect(await client.signInNow(), isTrue);
      });

      test('self-review: no double counting of the same attempts across the two ledgers', () async {
        backend.login = _Mode.reject;
        final client = clientWithGuardStore();
        for (var i = 0; i < 3; i++) {
          await client.signInNow();
          clock.advance(const Duration(seconds: 1));
        }
        // 3 persisted + the same 3 in-isolate must count as 3, not 6.
        expect(await client.signInNow(), isFalse); // 4th: rejected by server
        expect(backend.loginPosts, 4);
      });

      test('adversarial: malformed guard JSON never throws, never permits an automatic login, and keeps readable locks', () async {
        final lock = lockMs();
        final unlocked = <String>[
          'null',
          '[]',
          '"str"',
          '42',
          'true',
          '',
          '{"attempts":{}}',
          '{"attempts":"x"}',
          '{"attempts":[null,"a",{},1.5,true]}',
          '{"attempts":[-8640000000000001, 8640000000000001]}',
          '{"consecutiveFailures":"x"}',
          '{"consecutiveFailures":-3}',
          '{"blockedUntil":99999999999999999999}',
          '{"userActionRequired":"yes"}',
          '{"ceilingHold":1}',
        ];
        final locked = <String>[
          '{"attempts":"x","rateLimitedUntil":$lock}',
          '{"attempts":"x","rateLimitedUntil":"$lock"}',
          '{"attempts":"x","rateLimitedUntil":$lock.0}',
          '{"blockedUntil":"bad","rateLimitedUntil":$lock}',
        ];

        for (final raw in [...unlocked, ...locked]) {
          LoginAttemptGuard.resetIsolateStateForTest();
          guardStore = _FlakyStorage();
          handoff.clear();
          final client = clientWithGuardStore();
          await keys.clearAuthSession();
          await setRaw(raw);
          final noncesBefore = backend.nonceGets;

          final auto = await client.ensureWalletSession();
          final strictOk = () {
            try {
              LoginGuardState.decode(raw);
              return true;
            } catch (_) {
              return false;
            }
          }();
          if (!strictOk) {
            expect(auto, isFalse, reason: 'automatic on corrupt: $raw');
            expect(backend.nonceGets, noncesBefore, reason: raw);
          }

          await keys.clearAuthSession();
          final manualNonces = backend.nonceGets;
          final manual = await client.signInNow(); // must not throw
          if (locked.contains(raw)) {
            expect(manual, isFalse, reason: 'readable lock kept: $raw');
            expect(backend.nonceGets, manualNonces, reason: raw);
          }
        }
      });
    },
  );

  group('codex round 59: writes only ever add restrictions', () {
    late _FlakyStorage guardStore;

    KeyManager keyManagerOn(_FlakyStorage g) => KeyManager(
      biometric: BiometricService(
        client: FakeLocalAuthClient(authenticateResult: true),
      ),
      storage: storage,
      loginGuardStorage: g,
    );

    Future<void> setRaw(String raw) =>
        guardStore.write(key: LoginAttemptGuard.storageKey, value: raw);

    int lock12h() =>
        clock.now.add(const Duration(hours: 12)).millisecondsSinceEpoch;

    setUp(() => guardStore = _FlakyStorage());

    const nonFinite = ['NaN', 'Infinity', '-Infinity', '1e999'];

    for (final bad in nonFinite) {
      test(
        '[P1] salvage never throws on "$bad" and keeps a readable 12 h lock',
        () {
          final raw = '{"attempts":["$bad"],"rateLimitedUntil":${lock12h()}}';
          expect(() => LoginGuardState.salvage(raw), returnsNormally);
          expect(LoginGuardState.salvage(raw).rateLimitedUntil, isNotNull);
          expect(LoginGuardState.lenientTimestamp(bad), isNull);
        },
      );

      test(
        '[P1] "$bad" + 12 h lock: restart, wallet import, then Sign in again stays locked',
        () async {
          await setRaw('{"attempts":["$bad"],"rateLimitedUntil":${lock12h()}}');
          LoginAttemptGuard.resetIsolateStateForTest(); // a fresh isolate
          keys = keyManagerOn(guardStore);
          await storeVectorWallet(); // the import's best-effort release
          final client = newClient(keyManager: keys, auth: handoff);

          expect(await client.signInNow(), isFalse);
          expect(backend.nonceGets, 0);
        },
      );
    }

    test('[P1] one failed guard read during wallet import keeps the stored 12 h lock', () async {
      await setRaw(
        LoginGuardState(
          rateLimitedUntil: DateTime.fromMillisecondsSinceEpoch(
            lock12h(),
            isUtc: true,
          ),
        ).encode(),
      );
      final before = await guardStore.read(key: LoginAttemptGuard.storageKey);
      LoginAttemptGuard.resetIsolateStateForTest(); // a fresh isolate
      keys = keyManagerOn(guardStore);
      guardStore.failNextReads = 1; // transient I/O error at import time
      await storeVectorWallet(); // import completes...
      expect(await keys.hasWallet(), isTrue);
      expect(
        await guardStore.read(key: LoginAttemptGuard.storageKey),
        before,
        reason: '...without overwriting the ledger it could not read',
      );

      final client = newClient(keyManager: keys, auth: handoff);
      expect(await client.signInNow(), isFalse); // the later read succeeds
      expect(backend.nonceGets, 0);
    });

    test('a wallet import never rewrites a corrupt guard (Sign in again is the recovery)', () async {
      const raw = '{not json';
      await setRaw(raw);
      keys = keyManagerOn(guardStore);
      await storeVectorWallet();
      expect(await guardStore.read(key: LoginAttemptGuard.storageKey), raw);
    });

    test('a wallet import releases only user-releasable holds; attempts and the lock stay', () async {
      final t = clock.now.millisecondsSinceEpoch;
      await setRaw(
        '{"attempts":[$t,$t],"rateLimitedUntil":${lock12h()},'
        '"userActionRequired":true,"ceilingHold":true,'
        '"blockedUntil":${lock12h()},"consecutiveFailures":3}',
      );
      keys = keyManagerOn(guardStore);
      await storeVectorWallet();
      final after = LoginGuardState.decode(
        await guardStore.read(key: LoginAttemptGuard.storageKey),
      );
      expect(after.attempts, hasLength(2));
      expect(after.rateLimitedUntil, isNotNull);
      expect(after.userActionRequired, isFalse);
      expect(after.ceilingHold, isFalse);
      expect(after.blockedUntil, isNull);
    });

    test('future-stamped attempts are never shortened: they count until the clock passes them', () async {
      final soon = clock.now
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await setRaw('{"attempts":[$soon,$soon,$soon,$soon]}');
      final before = await guardStore.read(key: LoginAttemptGuard.storageKey);
      keys = keyManagerOn(guardStore);
      final client = newClient(keyManager: keys, auth: handoff);

      expect(await client.signInNow(), isFalse);
      expect(
        await guardStore.read(key: LoginAttemptGuard.storageKey),
        before,
        reason: 'a refused permit writes nothing',
      );
      clock.advance(const Duration(minutes: 30));
      expect(await client.signInNow(), isFalse);
      clock.advance(const Duration(minutes: 46)); // past stamp + window
      expect(await client.signInNow(), isTrue);
    });

    test('a stored lock is honoured in full, never shortened', () async {
      final far = clock.now.add(const Duration(days: 3)).millisecondsSinceEpoch;
      await setRaw('{"rateLimitedUntil":$far}');
      keys = keyManagerOn(guardStore);
      final client = newClient(keyManager: keys, auth: handoff);
      clock.advance(const Duration(hours: 25));
      expect(await client.signInNow(), isFalse);
      clock.advance(const Duration(days: 2));
      expect(await client.signInNow(), isTrue);
    });

    test('a server Retry-After is honoured in full', () async {
      final store = <String, String?>{};
      final g = LoginAttemptGuard(
        read: () async => store['g'],
        write: (v) async => store['g'] = v,
        clock: clock.call,
      );
      await g.recordOutcome(
        LoginOutcome.rateLimited,
        retryAfter: const Duration(hours: 30),
      );
      clock.advance(const Duration(hours: 29));
      expect(
        (await g.requestPermit(userInitiated: true)).status,
        LoginPermitStatus.rateLimited,
      );
    });

    LoginAttemptGuard memGuard(Map<String, String?> store) => LoginAttemptGuard(
      read: () async => store['g'],
      write: (v) async => store['g'] = v,
      clock: clock.call,
      random: () => 1.0,
    );

    test(
      'audit: a success never clears a hold set while the login was in flight',
      () async {
        final store = <String, String?>{};
        final g = memGuard(store);
        expect((await g.requestPermit(userInitiated: false)).allowed, isTrue);
        await g.holdForUser(); // e.g. a confirmed 401 on another client
        await g.recordOutcome(LoginOutcome.success);
        expect(await g.requiresUserAction(), isTrue);
        expect(LoginGuardState.decode(store['g']).userActionRequired, isTrue);
      },
    );

    test('audit: a failure never shortens a longer stored backoff', () async {
      final store = <String, String?>{
        'g': LoginGuardState(
          blockedUntil: clock.now.add(const Duration(hours: 3)),
        ).encode(),
      };
      final g = memGuard(store);
      await g.recordOutcome(LoginOutcome.transientFailure);
      expect(
        LoginGuardState.decode(store['g']).blockedUntil,
        clock.now.add(const Duration(hours: 3)),
      );
    });

    test(
      'audit: recording a 429 keeps a longer stored backoff as it is',
      () async {
        final far = clock.now.add(const Duration(hours: 3));
        final store = <String, String?>{
          'g': LoginGuardState(blockedUntil: far).encode(),
        };
        final g = memGuard(store);
        await g.recordOutcome(LoginOutcome.rateLimited);
        final after = LoginGuardState.decode(store['g']);
        expect(after.blockedUntil, far);
        expect(after.rateLimitedUntil, isNotNull);
      },
    );

    test(
      'recordOutcome never writes over a ledger it could not read or decode',
      () async {
        final store = <String, String?>{'g': '{not json'};
        final g = LoginAttemptGuard(
          read: () async => store['g'],
          write: (v) async => store['g'] = v,
          clock: clock.call,
        );
        await g.recordOutcome(LoginOutcome.success);
        await g.recordOutcome(LoginOutcome.transientFailure);
        await g.holdForUser();
        expect(store['g'], '{not json');
      },
    );
  });

  group('manager review: implausible values are treated as corrupt', () {
    late _FlakyStorage guardStore;

    ApiClient clientOn() {
      keys = KeyManager(
        biometric: BiometricService(
          client: FakeLocalAuthClient(authenticateResult: true),
        ),
        storage: storage,
        loginGuardStorage: guardStore,
      );
      return newClient(keyManager: keys, auth: handoff);
    }

    Future<void> setRaw(String raw) =>
        guardStore.write(key: LoginAttemptGuard.storageKey, value: raw);

    int inFuture(Duration d) => clock.now.add(d).millisecondsSinceEpoch;

    setUp(() => guardStore = _FlakyStorage());

    test(
      'a readable year-2100 lock: automatic refused, "Sign in again" recovers',
      () async {
        final y2100 = DateTime.utc(2100).millisecondsSinceEpoch;
        await setRaw('{"rateLimitedUntil":$y2100}');
        final client = clientOn();

        expect(await client.ensureWalletSession(), isFalse);
        expect(backend.nonceGets, 0);

        expect(await client.signInNow(), isTrue);
        expect(backend.loginPosts, 1);
        expect(
          LoginGuardState.decode(
            await guardStore.read(key: LoginAttemptGuard.storageKey),
          ).rateLimitedUntil,
          isNull,
          reason: 'the impossible lock is dropped by the explicit recovery',
        );
      },
    );

    test(
      'a plausible 6-day lock is honoured in full, never shortened',
      () async {
        final raw = '{"rateLimitedUntil":${inFuture(const Duration(days: 6))}}';
        await setRaw(raw);
        final client = clientOn();

        expect(await client.signInNow(), isFalse);
        clock.advance(const Duration(days: 5, hours: 23));
        expect(await client.signInNow(), isFalse);
        expect(await guardStore.read(key: LoginAttemptGuard.storageKey), raw);
        clock.advance(const Duration(hours: 2));
        expect(await client.signInNow(), isTrue);
      },
    );

    test('attempts stamped beyond 7 days are implausible; a plausible lock beside them is kept', () async {
      final far = inFuture(const Duration(days: 30));
      final lock = inFuture(const Duration(hours: 5));
      await setRaw(
        '{"attempts":[$far,$far,$far,$far],"rateLimitedUntil":$lock}',
      );
      final client = clientOn();

      expect(await client.ensureWalletSession(), isFalse);
      expect(await client.signInNow(), isFalse, reason: 'the 5 h lock stays');
      clock.advance(const Duration(hours: 6));
      expect(
        await client.signInNow(),
        isTrue,
        reason: 'the far attempts were dropped',
      );
    });

    test(
      'a server Retry-After beyond 7 days is recorded as the 7-day maximum',
      () async {
        final store = <String, String?>{};
        final g = LoginAttemptGuard(
          read: () async => store['g'],
          write: (v) async => store['g'] = v,
          clock: clock.call,
        );
        await g.recordOutcome(
          LoginOutcome.rateLimited,
          retryAfter: const Duration(days: 30),
        );
        expect(
          LoginGuardState.decode(store['g']).rateLimitedUntil,
          clock.now.add(LoginAttemptGuard.maxPlausibleLock),
        );
        clock.advance(const Duration(days: 6));
        expect(
          (await g.requestPermit(userInitiated: true)).status,
          LoginPermitStatus.rateLimited,
        );
      },
    );
  });
}

/// In-memory storage whose reads or writes can be made to throw.
class _FlakyStorage implements KeyValueStorage {
  final Map<String, String?> _values = <String, String?>{};
  bool failReads = false;

  /// Fails only the next N reads (a transient I/O error).
  int failNextReads = 0;
  bool failWrites = false;

  /// Accepts writes but never stores them (a non-durable store).
  bool dropWrites = false;

  @override
  Future<void> deleteAll() async => _values.clear();

  @override
  Future<String?> read({required String key}) async {
    if (failReads) throw StateError('read failed (test)');
    if (failNextReads > 0) {
      failNextReads--;
      throw StateError('transient read failure (test)');
    }
    return _values[key];
  }

  @override
  Future<void> write({required String key, String? value}) async {
    if (failWrites) throw StateError('write failed (test)');
    if (dropWrites) return;
    _values[key] = value;
  }
}
