import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService(client: ref.read(localAuthClientProvider));
});

final localAuthClientProvider = Provider<LocalAuthClient>((ref) {
  return PlatformLocalAuthClient();
});

class BiometricService {
  final LocalAuthClient _client;

  BiometricService({LocalAuthClient? client})
    : _client = client ?? PlatformLocalAuthClient();

  /// Whether the platform supports biometric checks.
  /// Always false on web.
  Future<bool> canCheckBiometrics() async {
    if (kIsWeb) return false;
    try {
      return await _client.canCheckBiometrics() ||
          await _client.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Authenticate the user. On web, biometrics are unavailable so this
  /// returns true (authentication is skipped; web key storage is
  /// already unencrypted — see KeyManager web warning).
  Future<bool> authenticate({
    String reason = 'Authenticate to continue',
  }) async {
    if (kIsWeb) return true;
    try {
      final supported =
          await _client.isDeviceSupported() ||
          await _client.canCheckBiometrics();
      if (!supported) return false;
      // One platform prompt offers biometrics or the device PIN/password.
      // Cancellation ends this attempt; it never opens another prompt.
      return await _client.authenticate(reason: reason, biometricOnly: false);
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return [];
    try {
      return await _client.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }
}

abstract class LocalAuthClient {
  Future<bool> canCheckBiometrics();

  Future<bool> isDeviceSupported();

  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  });

  Future<List<BiometricType>> getAvailableBiometrics();
}

class PlatformLocalAuthClient implements LocalAuthClient {
  final LocalAuthentication _auth;

  PlatformLocalAuthClient({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  @override
  Future<bool> canCheckBiometrics() => _auth.canCheckBiometrics;

  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) {
    return _auth.authenticate(
      localizedReason: reason,
      biometricOnly: biometricOnly,
      persistAcrossBackgrounding: true,
    );
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() {
    return _auth.getAvailableBiometrics();
  }
}
