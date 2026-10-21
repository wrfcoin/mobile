import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web3dart/credentials.dart';
import 'package:web3dart/crypto.dart';

import '../../core/auth/auth_handoff.dart';
import '../../core/constants/api_constants.dart';
import '../auth/login_attempt_guard.dart';
import '../crypto/key_manager.dart';
import '../crypto/ed25519_wallet_login.dart';
import '../crypto/wallet_setup_service.dart';
import '../../features/collector/data/services/station_submit_token_store.dart';
import '../../features/collector/data/services/station_submit_auth_interceptor.dart';
import 'dio_adapter_stub.dart' if (dart.library.io) 'dio_adapter_native.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    keyManager: ref.read(keyManagerProvider),
    authHandoff: ref.read(authHandoffControllerProvider),
    stationSubmitTokens: ref.read(stationSubmitTokenStoreProvider),
  );
});

class ApiClient {
  late final Dio dio;
  final _AuthSessionCoordinator? _authSession;
  final bool _allowUnauthenticatedRequests;

  static BaseOptions get _defaultOptions => BaseOptions(
    baseUrl: ApiConstants.effectiveBaseUrl,
    connectTimeout: ApiConstants.connectTimeout,
    receiveTimeout: ApiConstants.receiveTimeout,
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
  );

  /// Creates a Dio instance with certificate pinning applied on native platforms.
  static Dio _createDio(BaseOptions options) {
    final dio = Dio(options);
    final adapter = createPinnedAdapter();
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }
    return dio;
  }

  ApiClient({
    Dio? dio,
    Dio? authDio,
    StationSubmitTokenStore? stationSubmitTokens,
    KeyManager? keyManager,
    AuthHandoffController? authHandoff,
    Ed25519LoginExpectation? ed25519LoginExpectation,
    this._allowUnauthenticatedRequests = false,
    // False for Workmanager isolates: they may use or refresh a session but
    // never start a wallet login, so only the foreground isolate writes the
    // login guard (mobile#313 review: no cross-isolate lost updates).
    bool canStartLogin = true,
    // Test seams for the login guard's clock and jitter source.
    DateTime Function()? loginGuardClock,
    double Function()? loginGuardRandom,
  }) : _authSession = keyManager == null
           ? null
           : _AuthSessionCoordinator(
               keyManager: keyManager,
               authHandoff: authHandoff,
               authDio: authDio ?? _createDio(_defaultOptions),
               ed25519LoginExpectation:
                   ed25519LoginExpectation ??
                   Ed25519LoginExpectation.configured(),
               loginGuard: LoginAttemptGuard(
                 read: keyManager.readLoginGuardState,
                 write: keyManager.writeLoginGuardState,
                 clock: loginGuardClock,
                 random: loginGuardRandom,
               ),
               canStartLogin: canStartLogin,
             ) {
    if (dio != null) {
      this.dio = dio;
      this.dio.interceptors.insert(
        0,
        StationSubmitAuthInterceptor(
          this.dio,
          stationSubmitTokens ?? StationSubmitTokenStore(),
        ),
      );
      return;
    }

    this.dio = _createDio(_defaultOptions);

    final interceptors = <Interceptor>[
      _RetryInterceptor(this.dio),
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (obj) {}, // Suppress logs in production
      ),
    ];

    final authSession = _authSession;
    if (authSession != null) {
      interceptors.insert(0, _AuthInterceptor(this.dio, authSession));
    }

    this.dio.interceptors.addAll(interceptors);
    this.dio.interceptors.insert(
      0,
      StationSubmitAuthInterceptor(
        this.dio,
        stationSubmitTokens ?? StationSubmitTokenStore(),
      ),
    );
  }

  /// Ensures a session for automatic callers (sync, wallet screen). It may
  /// renew a session with its refresh token, but it never starts a wallet
  /// login: that needs the biometric-gated key, and only an explicit
  /// [signInNow] may prompt for it (mobile#320). Without a session it says
  /// "Not signed in" through the wallet-connect handoff.
  Future<bool> ensureWalletSession() async {
    if (_authSession == null) return _allowUnauthenticatedRequests;
    return _authSession.ensureAuthenticated();
  }

  /// An explicit, user-initiated sign-in (the Sign in button, or once right
  /// after a wallet is created). One biometric prompt, then at most one
  /// nonce and one login; a cancelled prompt sends nothing and is not
  /// retried. It may lift an automatic-login hold, but it still respects a
  /// 429 lockout and the absolute per-window login cap.
  Future<bool> signInNow() async {
    if (_authSession == null) return _allowUnauthenticatedRequests;
    return _authSession.signInNow();
  }
}

class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  final _AuthSessionCoordinator _authSession;

  _AuthInterceptor(this._dio, this._authSession);

  bool _isAuthRoute(String path) {
    return path.endsWith(ApiConstants.walletLogin) ||
        path.endsWith(ApiConstants.authRefresh);
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isAuthRoute(options.path) ||
        options.extra['stationSubmitAuth'] == true) {
      handler.next(options);
      return;
    }

    final token = await _authSession.getOrCreateToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final alreadyRetried = err.requestOptions.extra['authRetried'] == true;
    if (err.requestOptions.extra['stationSubmitAuth'] == true) {
      handler.next(err);
      return;
    }

    // Value-moving writes must not be replayed even after a successful refresh.
    // The next explicit operation can renew the session before submission.
    // noRetry controls transient HTTP retries; reads/onboarding may still renew auth.
    if (err.requestOptions.extra['noAuthRetry'] == true) {
      if (status == 401) await _authSession.clearAccessToken();
      handler.next(err);
      return;
    }

    if (status == 401 &&
        !alreadyRetried &&
        !_isAuthRoute(err.requestOptions.path)) {
      // Only the access token is suspect here; the refresh token decides.
      await _authSession.clearAccessToken();

      final token = await _authSession.getOrCreateToken();
      if (token == null) {
        // No fresh session: the refresh failed transiently (the refresh token
        // is kept for later), or it was rejected and the session is already
        // cleared, or a login is held or failed (the login guard recorded
        // why). Nothing here is a confirmed rejection of a fresh session, so
        // neither the session nor a user hold is touched.
        handler.next(err);
        return;
      }

      final retried = err.requestOptions;
      retried.extra['authRetried'] = true;
      retried.headers['Authorization'] = 'Bearer $token';
      try {
        final response = await _dio.fetch(retried);
        handler.resolve(response);
        return;
      } on DioException catch (retryError) {
        final retryStatus = retryError.response?.statusCode;
        if (retryStatus == 401 || retryStatus == 403) {
          // Confirmed: the server rejects even a freshly issued session.
          await _authSession.handleConfirmedAuthRejection();
        }
        // Anything else (offline, timeout, 5xx) says nothing about the
        // session: keep it.
        handler.next(err);
        return;
      } catch (_) {
        handler.next(err);
        return;
      }
    }

    handler.next(err);
  }
}

class _AuthSessionCoordinator {
  final KeyManager _keyManager;
  final Dio _authDio;
  final AuthHandoffController? _authHandoff;
  final Ed25519LoginExpectation _ed25519LoginExpectation;
  final LoginAttemptGuard _loginGuard;
  final bool _canStartLogin;

  /// One token request at a time per isolate, shared by every coordinator:
  /// the foreground holds several ApiClients (the provider's and each
  /// SyncWorker's), and they must not refresh or log in side by side.
  static Future<String?>? _inFlightTokenRequest;

  _AuthSessionCoordinator({
    required this._keyManager,
    required this._authHandoff,
    required this._authDio,
    required this._ed25519LoginExpectation,
    required this._loginGuard,
    required this._canStartLogin,
  });

  Future<bool> ensureAuthenticated() async {
    final token = await getOrCreateToken();
    return token != null && token.isNotEmpty;
  }

  Future<bool> signInNow() async {
    await _dropPreEd25519Session();
    final cached = await _keyManager.getAuthToken();
    if (cached != null) {
      _authHandoff?.clear();
      return true;
    }
    if (!_canStartLogin) return false;
    // Let an in-flight attempt settle first, then own the slot: an automatic
    // caller arriving meanwhile waits for this sign-in instead of racing it.
    while (true) {
      while (_inFlightTokenRequest != null) {
        await _inFlightTokenRequest;
      }
      final completedToken = await _keyManager.getAuthToken();
      if (completedToken != null) {
        _authHandoff?.clear();
        return true;
      }
      // The storage read yielded: another caller may now own the slot.
      if (_inFlightTokenRequest != null) continue;
      final request = _obtainToken(userInitiated: true);
      _inFlightTokenRequest = request;
      try {
        final token = await request;
        return token != null && token.isNotEmpty;
      } catch (_) {
        // Never surface an exception to the button; the handoff carries why.
        return false;
      } finally {
        if (identical(_inFlightTokenRequest, request)) {
          _inFlightTokenRequest = null;
        }
      }
    }
  }

  Future<void> clearAccessToken() async {
    await _keyManager.clearAccessToken();
  }

  Future<void> clearSession() async {
    await _keyManager.clearAuthSession();
  }

  /// The server rejected a freshly issued session (retry 401/403).
  Future<void> handleConfirmedAuthRejection() async {
    await clearSession();
    // Hold automatic logins so this cannot become a 401 -> login -> 401 loop
    // (mobile#313). Only the foreground isolate writes the guard.
    if (_canStartLogin) {
      await _loginGuard.holdForUser();
    }
    _authHandoff?.requireWalletConnect(
      reason: AuthHandoffReason.sessionExpired,
      message: 'Session expired. Reconnect your wallet to continue.',
    );
  }

  Future<String?> getOrCreateToken() async {
    await _dropPreEd25519Session();
    final cached = await _keyManager.getAuthToken();
    if (cached != null) return cached;

    final inFlight = _inFlightTokenRequest;
    if (inFlight != null) {
      await inFlight;
      // Whatever it produced is in storage now (or nothing was).
      return _keyManager.getAuthToken();
    }

    final request = _obtainToken();
    _inFlightTokenRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlightTokenRequest, request)) {
        _inFlightTokenRequest = null;
      }
    }
  }

  /// An ed25519 wallet installed before backend#1208 holds a session whose
  /// JWT `sub` is its secp256k1 login address, which the owner-bound wallet
  /// routes reject (403). Refreshing keeps that `sub`, so drop the session
  /// once and log in again with the ed25519 key.
  Future<void> _dropPreEd25519Session() async {
    if (await _keyManager.getKeyScheme() != KeyManager.canonicalKeyScheme) {
      return;
    }
    if (await _keyManager.getAuthWalletScheme() ==
        KeyManager.ed25519AuthScheme) {
      return;
    }
    if (await _keyManager.hasAuthSession()) {
      await _keyManager.clearAuthSession();
    }
  }

  Future<String?> _obtainToken({bool userInitiated = false}) async {
    if (!await _keyManager.hasWallet()) {
      return null;
    }

    final refreshed = await _refreshTokenFlow();
    switch (refreshed.kind) {
      case _RefreshKind.renewed:
        return refreshed.jwt;
      case _RefreshKind.transient:
        // Offline, timeout or a server error: a wallet login would fail the
        // same way and cost login budget. Keep the refresh token, retry later.
        return null;
      case _RefreshKind.none:
      case _RefreshKind.rejected:
        break;
    }

    if (!_canStartLogin) {
      // A Workmanager isolate: leave the login to the foreground app.
      return null;
    }

    if (!userInitiated) {
      // mobile#320: a wallet login unlocks the key behind a biometric
      // prompt. An automatic caller (a screen load, a sync, the 401 retry)
      // must never pop that prompt, or re-pop it after a cancel, so it only
      // says that nobody is signed in and waits for the user's Sign in.
      _raiseNotSignedIn();
      return null;
    }

    // Every wallet-connect handoff this coordinator raises is mirrored by a
    // persisted guard hold (a rejection, a 429, the ceiling, or an
    // unrecoverable 401). Unlike the in-memory handoff, the hold is seen by
    // the Workmanager isolates, survives a restart and a "Dismiss", and is
    // released only by an explicit sign-in or a newly stored wallet.
    return _walletLoginFlow(userInitiated: userInitiated);
  }

  /// Offers Sign in, unless a more specific message (a lock, a rejection) is
  /// already showing.
  void _raiseNotSignedIn() {
    final handoff = _authHandoff;
    if (handoff == null || handoff.message != null) return;
    handoff.requireWalletConnect(
      reason: AuthHandoffReason.notSignedIn,
      message: 'Not signed in. Tap Sign in to continue.',
    );
  }

  /// The user did not unlock the wallet key: the prompt was cancelled, or
  /// the device could not show it. Nothing was sent, and nothing retries.
  String? _keyUnlockFailed() {
    _authHandoff?.requireWalletConnect(
      reason: AuthHandoffReason.notSignedIn,
      message:
          'Not signed in: the wallet key was not unlocked. Tap Sign in to '
          'try again.',
    );
    return null;
  }

  /// Asks the login guard for a permit. Surfaces holds to the user.
  Future<bool> _permitLogin({required bool userInitiated}) async {
    final permit = await _loginGuard.requestPermit(
      userInitiated: userInitiated,
    );
    switch (permit.status) {
      case LoginPermitStatus.allowed:
        return true;
      case LoginPermitStatus.backoff:
        return false;
      case LoginPermitStatus.storageError:
        _authHandoff?.requireWalletConnect(
          reason: AuthHandoffReason.sessionExpired,
          message:
              'Sign-in is paused: this device\'s secure storage could not be '
              'read or written. Restart the app and tap "Sign in again". If '
              'it keeps failing, re-import the wallet from its recovery '
              'phrase.',
        );
        return false;
      case LoginPermitStatus.userActionRequired:
      case LoginPermitStatus.unavailable:
        _authHandoff?.requireWalletConnect(
          reason: AuthHandoffReason.sessionExpired,
          message:
              'Automatic sign-in is paused to protect the login limit. '
              'Tap "Sign in again" to continue.',
        );
        return false;
      case LoginPermitStatus.rateLimited:
      case LoginPermitStatus.windowCapReached:
        final until = permit.until?.toLocal();
        final hhmm = until == null
            ? 'later'
            : '${until.hour.toString().padLeft(2, '0')}:'
                  '${until.minute.toString().padLeft(2, '0')}';
        _authHandoff?.requireWalletConnect(
          reason: AuthHandoffReason.sessionExpired,
          message:
              'Too many sign-in attempts. Sign-in is paused until $hhmm to '
              'avoid a server lockout.',
        );
        return false;
    }
  }

  /// Classifies a failed auth request (nonce or login).
  static LoginOutcome _outcomeOf(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 429) return LoginOutcome.rateLimited;
      if (status != null && status >= 400 && status < 500) {
        return LoginOutcome.rejected;
      }
    }
    return LoginOutcome.transientFailure;
  }

  static Duration? _retryAfter(Object error) {
    if (error is! DioException) return null;
    final raw = error.response?.headers.value('retry-after');
    final seconds = raw == null ? null : int.tryParse(raw.trim());
    return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
  }

  Future<void> _recordFailure(Object error) {
    return _loginGuard.recordOutcome(
      _outcomeOf(error),
      retryAfter: _retryAfter(error),
    );
  }

  Future<_RefreshResult> _refreshTokenFlow() async {
    final refreshToken = await _keyManager.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return const _RefreshResult(_RefreshKind.none);
    }

    try {
      final response = await _authDio.post(
        ApiConstants.authRefresh,
        data: {'refreshToken': refreshToken},
      );

      final payload = _unwrapApiPayload(response.data);
      final jwt = payload['jwt'] as String?;
      if (jwt == null || jwt.isEmpty) {
        // A 2xx without a token is a server fault, not a verdict on the
        // refresh token: keep it.
        return const _RefreshResult(_RefreshKind.transient);
      }

      await _keyManager.storeAuthSession(
        jwt: jwt,
        refreshToken: payload['refreshToken'] as String? ?? refreshToken,
        expiresInSeconds: (payload['expiresIn'] as num?)?.toInt() ?? 900,
        // The backend keeps the wallet scheme across refresh.
        walletScheme: await _keyManager.getAuthWalletScheme(),
      );

      _authHandoff?.clear();
      return _RefreshResult(_RefreshKind.renewed, jwt);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      // Only a definitive auth rejection ends the session (mobile#314). The
      // backend answers every refresh failure with 401, and an auth error
      // may also come back as 403. Connection errors, timeouts, 429 and 5xx
      // keep the refresh token for a later retry.
      if (status == 401 || status == 403) {
        await _keyManager.clearAuthSession();
        return const _RefreshResult(_RefreshKind.rejected);
      }
      return const _RefreshResult(_RefreshKind.transient);
    } catch (_) {
      return const _RefreshResult(_RefreshKind.transient);
    }
  }

  Future<String?> _walletLoginFlow({required bool userInitiated}) async {
    if (await _keyManager.getKeyScheme() == KeyManager.canonicalKeyScheme) {
      return _ed25519WalletLoginFlow(userInitiated: userInitiated);
    }
    return _evmWalletLoginFlow(userInitiated: userInitiated);
  }

  /// ed25519 login for `ed25519-slip10` wallets (backend#1205/#1208).
  ///
  /// The JWT `sub` becomes the wallet's chain address, which is what the
  /// owner-bound wallet routes (`/wallet/:address/nonce`, `/wallet/send`)
  /// compare against. The client signs the UTF-8 bytes of the server-issued
  /// `message` exactly as returned, with plain ed25519 (no prefix, no hash).
  /// It never builds the challenge locally.
  Future<String?> _ed25519WalletLoginFlow({required bool userInitiated}) async {
    final storedAddress = await _keyManager.getAddress();
    if (storedAddress == null || storedAddress.isEmpty) {
      return null;
    }
    final address = storedAddress.trim().toLowerCase();

    // Biometric-gated read of the ed25519 seed.
    final seed = await _keyManager.getPrivateKey();
    if (seed == null || seed.isEmpty) {
      return _keyUnlockFailed();
    }

    var seedControlsAddress = false;
    try {
      final publicKey = await WalletSetupService().publicKeyFromEd25519Seed(
        seed,
      );
      seedControlsAddress =
          WalletSetupService().chainAddressFromEd25519(publicKey) == address;
    } catch (_) {
      seedControlsAddress = false;
    }
    if (!seedControlsAddress) {
      return _rejectEd25519Wallet();
    }

    // Every request below counts against the backend's login budget.
    if (!await _permitLogin(userInitiated: userInitiated)) {
      return null;
    }

    final String nonce;
    final String message;
    try {
      final nonceResponse = await _authDio.get(
        ApiConstants.walletNonce(address),
        queryParameters: const {'scheme': 'ed25519'},
      );
      final noncePayload = _unwrapApiPayload(nonceResponse.data);
      nonce = noncePayload['nonce'] as String? ?? '';
      message = noncePayload['message'] as String? ?? '';
      if (nonce.isEmpty ||
          message.isEmpty ||
          noncePayload['scheme'] != 'ed25519') {
        await _loginGuard.recordOutcome(LoginOutcome.rejected);
        return null;
      }
    } catch (error) {
      await _recordFailure(error);
      return null;
    }

    // Fail closed: the wallet key signs only a challenge that is exactly
    // the ed25519 login for this address, origin, chain and network, never
    // an arbitrary server-chosen payload such as a transfer preimage
    // (backend#1208 review, finding 2).
    final Ed25519WalletLoginProof proof;
    try {
      proof = await signEd25519WalletLogin(
        seedHex: seed,
        address: address,
        nonce: nonce,
        message: message,
        expected: _ed25519LoginExpectation,
      );
    } on Ed25519LoginChallengeRejected {
      await _loginGuard.recordOutcome(LoginOutcome.rejected);
      await _keyManager.clearAuthSession();
      _authHandoff?.requireWalletConnect(
        reason: AuthHandoffReason.sessionExpired,
        message: 'The server sent an unexpected login challenge. Nothing was signed.',
      );
      return null;
    }

    try {
      final response = await _authDio.post(
        ApiConstants.walletLogin,
        data: {
          'scheme': 'ed25519',
          'address': address,
          'pubkey': proof.publicKeyHex,
          'signature': proof.signatureHex,
          'nonce': nonce,
        },
      );

      final payload = _unwrapApiPayload(response.data);
      final jwt = payload['jwt'] as String?;
      if (jwt == null || jwt.isEmpty) {
        await _loginGuard.recordOutcome(LoginOutcome.rejected);
        return null;
      }

      await _keyManager.storeAuthSession(
        jwt: jwt,
        refreshToken: payload['refreshToken'] as String?,
        expiresInSeconds: (payload['expiresIn'] as num?)?.toInt() ?? 900,
        walletScheme: KeyManager.ed25519AuthScheme,
      );

      await _loginGuard.recordOutcome(LoginOutcome.success);
      _authHandoff?.clear();
      return jwt;
    } catch (error) {
      return _loginPostFailed(error);
    }
  }

  /// A failed login POST. A transport or server failure only backs off; a
  /// rejection or a 429 ends the session and asks the user.
  Future<String?> _loginPostFailed(Object error) async {
    final outcome = _outcomeOf(error);
    await _recordFailure(error);
    if (outcome == LoginOutcome.transientFailure) {
      return null;
    }
    await _keyManager.clearAuthSession();
    _authHandoff?.requireWalletConnect(
      reason: AuthHandoffReason.sessionExpired,
      message: outcome == LoginOutcome.rateLimited
          ? 'The server is limiting sign-ins. Automatic sign-in is paused; '
                'try again in an hour.'
          : 'Wallet authentication failed. Reconnect your wallet and try again.',
    );
    return null;
  }

  Future<String?> _rejectEd25519Wallet() async {
    await _keyManager.clearAuthSession();
    _authHandoff?.requireWalletConnect(
      reason: AuthHandoffReason.unsupportedWallet,
      message: 'Wallet address does not match its signing key. Re-import this wallet from its recovery phrase to continue.',
    );
    return null;
  }

  /// secp256k1 personal_sign login for legacy and private-key imports, which
  /// stay receive-only.
  Future<String?> _evmWalletLoginFlow({required bool userInitiated}) async {
    final walletAddress = await _keyManager.getLoginAddress();
    if (walletAddress == null || walletAddress.isEmpty) {
      return null;
    }

    final normalizedAddress = walletAddress.toLowerCase();
    if (!_isEvmAddress(normalizedAddress)) {
      await _keyManager.clearAuthSession();
      _authHandoff?.requireWalletConnect(
        reason: AuthHandoffReason.unsupportedWallet,
        message: 'This wallet uses a non-EVM address. Import an EVM (0x...) wallet for secure login.',
      );
      return null;
    }

    // Biometric-gated private key access for wallet-auth flow.
    final privateKey = await _keyManager.getLoginPrivateKey();
    if (privateKey == null || privateKey.isEmpty) {
      return _keyUnlockFailed();
    }

    final credentials = EthPrivateKey.fromHex(
      _canonicalHexPrivateKey(privateKey),
    );
    final derivedAddress = credentials.address.hex.toLowerCase();
    if (derivedAddress != normalizedAddress) {
      await _keyManager.clearAuthSession();
      _authHandoff?.requireWalletConnect(
        reason: AuthHandoffReason.unsupportedWallet,
        message: 'Wallet address does not match the private key for EVM signing. Re-import this wallet as EVM (0x...) to continue.',
      );
      return null;
    }

    // Every request below counts against the backend's login budget.
    if (!await _permitLogin(userInitiated: userInitiated)) {
      return null;
    }

    // Step 1: Request a challenge nonce from the server.
    // The backend stores this nonce in Redis with a short TTL and
    // validates it during login — client-generated nonces are rejected.
    final String nonce;
    final String message;
    try {
      final nonceResponse = await _authDio.get(
        ApiConstants.walletNonce(normalizedAddress),
      );
      final noncePayload = _unwrapApiPayload(nonceResponse.data);
      nonce = noncePayload['nonce'] as String? ?? '';
      message = noncePayload['message'] as String? ?? '';
      if (nonce.isEmpty || message.isEmpty) {
        await _loginGuard.recordOutcome(LoginOutcome.rejected);
        return null;
      }
    } catch (error) {
      await _recordFailure(error);
      return null;
    }

    // Step 2: Sign the server-issued message byte-for-byte. The backend binds
    // domain, address, chain, nonce and expiry into this exact challenge.
    final signature = bytesToHex(
      credentials.signPersonalMessageToUint8List(utf8.encode(message)),
      include0x: true,
    );

    try {
      final response = await _authDio.post(
        ApiConstants.walletLogin,
        data: {
          'address': normalizedAddress,
          'signature': signature,
          'nonce': nonce,
        },
      );

      final payload = _unwrapApiPayload(response.data);
      final jwt = payload['jwt'] as String?;
      if (jwt == null || jwt.isEmpty) {
        await _loginGuard.recordOutcome(LoginOutcome.rejected);
        return null;
      }

      await _keyManager.storeAuthSession(
        jwt: jwt,
        refreshToken: payload['refreshToken'] as String?,
        expiresInSeconds: (payload['expiresIn'] as num?)?.toInt() ?? 900,
      );

      await _loginGuard.recordOutcome(LoginOutcome.success);
      _authHandoff?.clear();
      return jwt;
    } catch (error) {
      return _loginPostFailed(error);
    }
  }

  bool _isEvmAddress(String address) {
    return RegExp(r'^0x[a-f0-9]{40}$').hasMatch(address);
  }

  String _canonicalHexPrivateKey(String privateKey) {
    final trimmed = privateKey.trim();
    return trimmed.startsWith('0x') ? trimmed : '0x$trimmed';
  }

  Map<String, dynamic> _unwrapApiPayload(dynamic raw) {
    if (raw is Map<String, dynamic> && raw['data'] is Map<String, dynamic>) {
      return raw['data'] as Map<String, dynamic>;
    }

    if (raw is Map<String, dynamic>) {
      return raw;
    }

    return <String, dynamic>{};
  }
}

enum _RefreshKind { none, renewed, transient, rejected }

class _RefreshResult {
  const _RefreshResult(this.kind, [this.jwt]);

  final _RefreshKind kind;
  final String? jwt;
}

class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  static const _maxRetries = 2;

  _RetryInterceptor(this._dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // A per-request opt-out from timeout/5xx retry for writes and lifecycle reads.
    // Auth refresh/replay is controlled separately by noAuthRetry.
    if (err.requestOptions.extra['noRetry'] == true) {
      handler.next(err);
      return;
    }
    final retryCount = err.requestOptions.extra['retryCount'] ?? 0;

    if (_shouldRetry(err) && retryCount < _maxRetries) {
      await Future.delayed(Duration(seconds: retryCount + 1));
      err.requestOptions.extra['retryCount'] = retryCount + 1;

      try {
        final response = await _dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (_) {
        // Fall through to reject
      }
    }

    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);
  }
}
