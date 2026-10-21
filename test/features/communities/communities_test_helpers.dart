/// Minimal test fakes for the communities feature tests.
///
/// We deliberately do NOT import from test_helpers/fakes.dart because that
/// file transitively imports weather_repository_impl.dart, which depends on
/// forecast_detail_model.freezed.dart — a pre-existing stale generated file
/// that causes compilation failures.  Only add imports here that do NOT pull
/// in that chain.
library;

import 'package:local_auth/local_auth.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

// ── InMemoryKeyValueStorage ───────────────────────────────────────────────────

class InMemoryKeyValueStorage implements KeyValueStorage {
  final Map<String, String?> _values = <String, String?>{};

  @override
  Future<void> deleteAll() async => _values.clear();

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, String? value}) async {
    _values[key] = value;
  }
}

// ── FakeLocalAuthClient ───────────────────────────────────────────────────────

class FakeLocalAuthClient implements LocalAuthClient {
  FakeLocalAuthClient({
    this.canCheck = true,
    this.deviceSupported = true,
    this.authenticateResult = true,
    this.availableBiometrics = const [BiometricType.fingerprint],
  });

  final bool canCheck;
  final bool deviceSupported;
  final bool authenticateResult;
  final List<BiometricType> availableBiometrics;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async =>
      authenticateResult;

  @override
  Future<bool> canCheckBiometrics() async => canCheck;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      availableBiometrics;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;
}
