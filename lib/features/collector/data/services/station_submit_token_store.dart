import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/crypto/key_manager.dart';

final stationSubmitTokenStoreProvider = Provider<StationSubmitTokenStore>(
  (ref) => StationSubmitTokenStore(),
);

/// Native-only, station-bound credential for /api/weather/submit. It is not
/// the account JWT or collect signing key. The collect-key secure namespace
/// permits background reads and is erased by the existing Emergency Wipe.
class StationSubmitTokenStore {
  StationSubmitTokenStore({KeyValueStorage? storage, bool? native})
    : _storage = storage ?? const SecureKeyValueStorage.collectKey(),
      _native = native ?? !kIsWeb;

  final KeyValueStorage _storage;
  final bool _native;
  static final _station = RegExp(r'^mob-[0-9a-f]{32}$');
  static final _credential = RegExp(r'^[0-9a-f]{64}$');

  void _admit(String stationId) {
    if (!_native || !_station.hasMatch(stationId)) {
      throw StateError('Secure station credential storage is unavailable.');
    }
  }

  /// Owner transfers a private JSON packet with stationId and token. Binding
  /// prevents a credential for another station being imported accidentally.
  /// Never include any input in errors or logs.
  Future<void> importPacket(String stationId, String packet) async {
    _admit(stationId);
    Object? decoded;
    try {
      decoded = jsonDecode(packet);
    } catch (_) {
      throw const FormatException('Station credential packet is invalid.');
    }
    if (decoded is! Map ||
        decoded['stationId'] != stationId ||
        decoded['token'] is! String ||
        !_credential.hasMatch(decoded['token'] as String)) {
      throw const FormatException('Station credential packet is invalid.');
    }
    await _storage.write(
      key: 'weather_submit_token:$stationId',
      value: decoded['token'] as String,
    );
  }

  Future<String?> read(String stationId) async {
    _admit(stationId);
    final token = await _storage.read(key: 'weather_submit_token:$stationId');
    if (token != null && !_credential.hasMatch(token)) {
      throw StateError('Station credential is unavailable.');
    }
    return token;
  }

  Future<void> remove(String stationId) async {
    _admit(stationId);
    await _storage.write(key: 'weather_submit_token:$stationId', value: null);
  }
}
