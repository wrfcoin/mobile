import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

final fcmTokenServiceProvider = Provider<FcmTokenService>((ref) {
  return FcmTokenService(apiClient: ref.watch(apiClientProvider));
});

/// Manages FCM push notification token lifecycle:
/// - Storage in [FlutterSecureStorage] (token value)
/// - Registration / refresh against the backend
/// - Staleness detection via a last-registered timestamp in [SharedPreferences]
///
/// NOTE: FCM itself is not a direct dependency in pubspec — the app uses
/// [flutter_local_notifications] for on-device alerts.  The FCM SDK (firebase_messaging)
/// is intentionally omitted from this workspace's pubspec because it requires
/// google-services.json / GoogleService-Info.plist that are CI secrets.
/// This service is therefore written against an abstract [FcmPlatform] interface
/// so the real Firebase implementation can be wired up at a later stage, and so
/// the full logic (storage, registration, refresh) is testable without Firebase.
abstract class FcmPlatform {
  /// Returns the current device push token, or null if unavailable.
  Future<String?> getToken();

  /// Fires whenever the platform rotates the token.
  Stream<String?> get onTokenRefresh;
}

class FcmTokenService {
  FcmTokenService({
    required this._apiClient,
    FlutterSecureStorage? secureStorage,
    this._platform,
    Duration? retryBaseDelay,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _retryBaseDelay = retryBaseDelay ?? _retryBaseDelayDefault;

  static const _tokenKey = 'fcm_push_token';
  static const _registeredAtKey = 'fcm_token_registered_at_ms';

  /// Re-register the token if it is older than this duration.
  static const _refreshInterval = Duration(days: 7);

  /// Maximum registration attempts before giving up on a single call.
  static const _maxRetries = 3;

  /// Base delay for exponential backoff (injectable for testing).
  static const _retryBaseDelayDefault = Duration(seconds: 2);

  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage;
  final FcmPlatform? _platform;
  final Duration _retryBaseDelay;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Call once on app startup.  Fetches the current platform token, stores it
  /// securely, registers it with the backend if not already registered (or if
  /// the token changed / is stale), and subscribes to future rotations.
  Future<void> initialize() async {
    final platform = _platform;
    if (platform == null) return; // Firebase not yet wired up

    final token = await platform.getToken();
    if (token != null) {
      await _handleToken(token);
    }

    // Listen for token rotation; re-register immediately when it happens.
    platform.onTokenRefresh.listen((newToken) async {
      if (newToken != null) {
        await _handleToken(newToken, forceRegister: true);
      }
    });
  }

  /// Returns the locally stored token, if any.
  Future<String?> getStoredToken() => _secureStorage.read(key: _tokenKey);

  /// Removes the stored token and registration timestamp (e.g. on sign-out).
  Future<void> clearToken() async {
    await _secureStorage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_registeredAtKey);
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<void> _handleToken(String token, {bool forceRegister = false}) async {
    final stored = await _secureStorage.read(key: _tokenKey);
    final tokenChanged = stored != token;

    if (tokenChanged) {
      await _secureStorage.write(key: _tokenKey, value: token);
    }

    if (forceRegister || tokenChanged || await _isRegistrationStale()) {
      await _registerWithBackend(token);
    }
  }

  Future<bool> _isRegistrationStale() async {
    final prefs = await SharedPreferences.getInstance();
    final registeredAtMs = prefs.getInt(_registeredAtKey);
    if (registeredAtMs == null) return true;
    final registeredAt = DateTime.fromMillisecondsSinceEpoch(registeredAtMs);
    return DateTime.now().difference(registeredAt) > _refreshInterval;
  }

  Future<void> _registerWithBackend(String token) async {
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _apiClient.dio.post(
          '/notifications/push-token',
          data: {'token': token, 'platform': _platformName()},
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          _registeredAtKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        return;
      } catch (_) {
        final isLastAttempt = attempt == _maxRetries - 1;
        if (isLastAttempt) {
          // Registration failure is non-fatal; the token is stored locally
          // and will be retried on the next app start.
          return;
        }
        final delay = _retryBaseDelay * math.pow(2.0, attempt).toInt();
        await Future<void>.delayed(delay);
      }
    }
  }

  String _platformName() {
    // Resolved at call-site when firebase_messaging is added; defaulting to
    // 'unknown' is safe — the backend treats it as informational only.
    return 'unknown';
  }
}
