import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/biometric_service.dart';
import '../auth/login_attempt_guard.dart';

final keyManagerProvider = Provider<KeyManager>((ref) {
  return KeyManager(
    biometric: ref.read(biometricServiceProvider),
    storage: ref.read(keyValueStorageProvider),
  );
});

final keyValueStorageProvider = Provider<KeyValueStorage>((ref) {
  return const SecureKeyValueStorage();
});

class KeyManager {
  final BiometricService _biometric;
  final KeyValueStorage _storage;

  final KeyValueStorage _guardStorage;

  /// [loginGuardStorage] holds the login-attempt guard (mobile#313). In
  /// production it is its own secure-storage namespace, so an Emergency
  /// Wipe of [storage] never touches it: there is no read-and-restore step
  /// that could fail open or be interrupted. A test fake [storage] without
  /// an explicit guard storage shares the fake.
  KeyManager({
    required this._biometric,
    KeyValueStorage? storage,
    KeyValueStorage? loginGuardStorage,
  }) : _storage = storage ?? const SecureKeyValueStorage(),
       _guardStorage =
           loginGuardStorage ??
           (storage == null || storage is SecureKeyValueStorage
               ? const SecureKeyValueStorage.loginGuard()
               : storage);

  /// Whether the platform provides encrypted key storage.
  /// On web, flutter_secure_storage falls back to unencrypted SharedPreferences.
  static bool get isSecurePlatform => !kIsWeb;

  static const _mnemonicKey = 'wrf_mnemonic';
  static const _privateKeyKey = 'wrf_private_key';
  static const _addressKey = 'wrf_address';
  static const _keySchemeKey = 'wrf_key_scheme';
  static const _loginPrivateKeyKey = 'wrf_login_private_key';
  static const _loginAddressKey = 'wrf_login_address';
  static const canonicalKeyScheme = 'ed25519-slip10';
  static const legacyKeyScheme = 'legacy-secp256k1-sha256';
  static const _jwtKey = 'wrf_jwt';
  static const _refreshTokenKey = 'wrf_refresh_token';
  static const _jwtExpiresAtKey = 'wrf_jwt_expires_at';
  static const _authWalletSchemeKey = 'wrf_auth_wallet_scheme';

  /// Marks an auth session minted by ed25519 wallet login (backend#1208),
  /// whose JWT `sub` is the chain address.
  static const ed25519AuthScheme = 'ed25519';

  // Rate limiting: track failed auth attempts
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  static const _maxAttempts = 5;
  static const _lockoutDuration = Duration(minutes: 2);

  Future<bool> hasWallet() async {
    final address = await _storage.read(key: _addressKey);
    return address != null;
  }

  Future<void> storeKeys({
    required String mnemonic,
    required String privateKey,
    required String address,
    String keyScheme = canonicalKeyScheme,
    String? loginPrivateKey,
    String? loginAddress,
  }) async {
    if (kIsWeb) {
      debugPrint(
        'WARNING: Keys stored in unencrypted web storage. '
        'Use a native build for production wallets.',
      );
    }
    await Future.wait([
      _storage.write(key: _mnemonicKey, value: mnemonic),
      _storage.write(key: _privateKeyKey, value: privateKey),
      _storage.write(key: _addressKey, value: address),
      _storage.write(key: _keySchemeKey, value: keyScheme),
      _storage.write(
        key: _loginPrivateKeyKey,
        value: loginPrivateKey ?? privateKey,
      ),
      _storage.write(key: _loginAddressKey, value: loginAddress ?? address),
      _storage.write(key: _jwtKey, value: null),
      _storage.write(key: _refreshTokenKey, value: null),
      _storage.write(key: _jwtExpiresAtKey, value: null),
      _storage.write(key: _authWalletSchemeKey, value: null),
    ]);
    // Creating or importing a wallet is an explicit user action: it
    // releases an automatic-login hold (mobile#313), but keeps the attempt
    // ledger, because the backend's login budget is per IP.
    await LoginAttemptGuard.releaseForNewWallet(
      read: readLoginGuardState,
      write: writeLoginGuardState,
    );
  }

  /// Persisted login-guard state (mobile#313), in its own storage namespace.
  Future<String?> readLoginGuardState() {
    return _guardStorage.read(key: LoginAttemptGuard.storageKey);
  }

  Future<void> writeLoginGuardState(String value) {
    return _guardStorage.write(key: LoginAttemptGuard.storageKey, value: value);
  }

  Future<String?> getAddress() async {
    return _storage.read(key: _addressKey);
  }

  Future<String?> getLoginAddress() async {
    return await _storage.read(key: _loginAddressKey) ?? getAddress();
  }

  Future<String?> getLoginPrivateKey() async {
    if (!await _authenticateForKeyAccess('login_private_key')) return null;
    return await _storage.read(key: _loginPrivateKeyKey) ??
        _storage.read(key: _privateKeyKey);
  }

  /// Existing installs predate the scheme marker and remain receive-only.
  Future<String> getKeyScheme() async {
    return await _storage.read(key: _keySchemeKey) ?? legacyKeyScheme;
  }

  Future<bool> canSignTransactions() async {
    return await getKeyScheme() == canonicalKeyScheme;
  }

  /// This wallet's own known non-spendable alias: a stored login address that
  /// differs from the canonical chain address of a canonical wallet. Null when
  /// nothing is positively known. Never inferred from address text.
  Future<String?> getOwnLegacyAlias() async {
    if (!await canSignTransactions()) return null;
    final address = await getAddress();
    final login = await _storage.read(key: _loginAddressKey);
    if (address == null || login == null || login.isEmpty) return null;
    return login.toLowerCase() == address.toLowerCase() ? null : login;
  }

  /// Returns the private key after biometric authentication.
  /// Returns null if authentication fails or the user is locked out.
  Future<String?> getPrivateKey() async {
    if (!await _authenticateForKeyAccess('private_key')) return null;
    return _storage.read(key: _privateKeyKey);
  }

  /// Returns the mnemonic after biometric authentication.
  /// Returns null if authentication fails or the user is locked out.
  Future<String?> getMnemonic() async {
    if (!await _authenticateForKeyAccess('mnemonic')) return null;
    return _storage.read(key: _mnemonicKey);
  }

  /// Emergency Wipe: deletes every wallet and session key. The login-attempt
  /// ledger lives in a separate namespace and is not touched, so wipe +
  /// re-import cannot reset the login cap or a 429 lock (mobile#313).
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  Future<void> storeAuthSession({
    required String jwt,
    String? refreshToken,
    required int expiresInSeconds,
    String? walletScheme,
  }) async {
    final expiresAt = DateTime.now()
        .toUtc()
        .add(Duration(seconds: expiresInSeconds))
        .millisecondsSinceEpoch
        .toString();

    await Future.wait([
      _storage.write(key: _jwtKey, value: jwt),
      _storage.write(key: _jwtExpiresAtKey, value: expiresAt),
      _storage.write(key: _authWalletSchemeKey, value: walletScheme),
      if (refreshToken != null)
        _storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }

  /// Whether any access or refresh token is stored.
  Future<bool> hasAuthSession() async {
    final jwt = await _storage.read(key: _jwtKey);
    final refresh = await _storage.read(key: _refreshTokenKey);
    return (jwt != null && jwt.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty);
  }

  /// Login scheme of the stored auth session, or null for an EVM session.
  Future<String?> getAuthWalletScheme() async {
    return _storage.read(key: _authWalletSchemeKey);
  }

  Future<String?> getAuthToken() async {
    final token = await _storage.read(key: _jwtKey);
    if (token == null || token.isEmpty) return null;

    final expiryRaw = await _storage.read(key: _jwtExpiresAtKey);
    if (expiryRaw == null) return token;

    final expiryMs = int.tryParse(expiryRaw);
    if (expiryMs == null) return token;

    // Consider tokens expired 30s early to avoid edge races. Only the access
    // token is dropped: the refresh token is what renews it without a new
    // wallet login (mobile#314).
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (nowMs >= (expiryMs - 30000)) {
      await clearAccessToken();
      return null;
    }

    return token;
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> clearAccessToken() async {
    await Future.wait([
      _storage.write(key: _jwtKey, value: null),
      _storage.write(key: _jwtExpiresAtKey, value: null),
    ]);
  }

  Future<void> clearAuthSession() async {
    await Future.wait([
      _storage.write(key: _jwtKey, value: null),
      _storage.write(key: _refreshTokenKey, value: null),
      _storage.write(key: _jwtExpiresAtKey, value: null),
      _storage.write(key: _authWalletSchemeKey, value: null),
    ]);
  }

  /// Mask address for display: show first 6 + last 4 chars
  static String maskAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  /// Whether the user is currently locked out from key access.
  bool get isLockedOut {
    if (_lockoutUntil == null) return false;
    if (DateTime.now().isAfter(_lockoutUntil!)) {
      _lockoutUntil = null;
      _failedAttempts = 0;
      return false;
    }
    return true;
  }

  /// Remaining lockout duration, or null if not locked out.
  Duration? get lockoutRemaining {
    if (!isLockedOut) return null;
    return _lockoutUntil!.difference(DateTime.now());
  }

  /// Gate key access behind biometric auth with rate limiting.
  Future<bool> _authenticateForKeyAccess(String keyType) async {
    if (isLockedOut) {
      debugPrint(
        '[KEY_AUDIT] Access denied ($keyType): locked out until $_lockoutUntil',
      );
      return false;
    }

    final authenticated = await _biometric.authenticate(
      reason: 'Authenticate to access wallet keys',
    );

    if (authenticated) {
      _failedAttempts = 0;
      debugPrint('[KEY_AUDIT] Access granted ($keyType)');
      return true;
    }

    _failedAttempts++;
    debugPrint(
      '[KEY_AUDIT] Access denied ($keyType): '
      'failed attempt $_failedAttempts/$_maxAttempts',
    );

    if (_failedAttempts >= _maxAttempts) {
      _lockoutUntil = DateTime.now().add(_lockoutDuration);
      debugPrint('[KEY_AUDIT] Lockout activated until $_lockoutUntil');
    }

    return false;
  }
}

abstract class KeyValueStorage {
  Future<void> write({required String key, String? value});

  Future<String?> read({required String key});

  Future<void> deleteAll();
}

class SecureKeyValueStorage implements KeyValueStorage {
  final FlutterSecureStorage _storage;

  const SecureKeyValueStorage()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(resetOnError: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          synchronizable: false,
        ),
      );

  /// The login-attempt guard's own namespace (mobile#313). It is separate from
  /// the wallet store, so the wallet store's `deleteAll` (Emergency Wipe)
  /// cannot remove it. `resetOnError` is off: an unreadable guard must fail
  /// closed, not be silently reset to an empty (permissive) ledger.
  const SecureKeyValueStorage.loginGuard()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          resetOnError: false,
          storageNamespace: 'wrfcoin_login_guard',
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          synchronizable: false,
          accountName: 'wrfcoin_login_guard',
        ),
      );

  /// The per-phone collect key's own namespace (design §11). Keystore-backed
  /// like the wallet store but with NO user-authentication requirement: the
  /// Workmanager isolate must read it with the app closed. It holds a key with
  /// no spending power. `resetOnError` is off so an unreadable store is
  /// reported (and a fresh key registered) instead of silently swapped.
  const SecureKeyValueStorage.collectKey()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          resetOnError: false,
          storageNamespace: 'wrfcoin_collect_key',
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          synchronizable: false,
          accountName: 'wrfcoin_collect_key',
        ),
      );

  @override
  Future<void> deleteAll() => _storage.deleteAll();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, String? value}) {
    return _storage.write(key: key, value: value);
  }
}
