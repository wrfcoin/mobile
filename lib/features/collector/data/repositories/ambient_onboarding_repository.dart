import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/api_client.dart';
import '../../../weather/domain/models/coarse_location.dart';

final ambientOnboardingRepositoryProvider =
    Provider<AmbientOnboardingRepository>(
      (ref) => AmbientOnboardingRepository(ref.watch(apiClientProvider)),
    );

class AmbientOnboardingProblem implements Exception {
  const AmbientOnboardingProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Account results and credentials are deliberately ephemeral and opaque.
/// Only devices from this verifier can be handed to registration.
class VerifiedAmbientAccount {
  VerifiedAmbientAccount._(
    this._apiKey,
    this._appKey,
    List<AmbientDevice> devices,
  ) : devices = List.unmodifiable(devices);
  final String _apiKey;
  final String _appKey;
  final List<AmbientDevice> devices;
}

class AmbientDevice {
  const AmbientDevice._(this._mac);
  final String _mac;
  String get label => 'Ambient station • ${_mac.substring(8)}';
}

class AmbientOnboardingRepository {
  AmbientOnboardingRepository(this._api);
  final ApiClient _api;

  Future<Map> _post(
    String path,
    Map<String, Object> body,
    CancelToken? cancel,
  ) async {
    try {
      if (cancel?.isCancelled ?? false) {
        throw const AmbientOnboardingProblem('Onboarding was cancelled.');
      }
      if (!await _api.ensureWalletSession()) {
        throw const AmbientOnboardingProblem(
          'Sign in from Wallet before connecting a station.',
        );
      }
      if (cancel?.isCancelled ?? false) {
        throw const AmbientOnboardingProblem('Onboarding was cancelled.');
      }
      final response = await _api.dio.post<Object?>(
        path,
        data: body,
        cancelToken: cancel,
        options: Options(
          followRedirects: false,
          extra: const {'noRetry': true},
        ),
      );
      if (response.data is! Map) {
        throw const AmbientOnboardingProblem(
          'The station service returned an incomplete response.',
        );
      }
      return response.data as Map;
    } on AmbientOnboardingProblem {
      rethrow;
    } on DioException catch (error) {
      // Never reflect a body, URL or exception that may contain provider keys.
      throw AmbientOnboardingProblem(switch (error.response?.statusCode) {
        401 || 403 => 'Sign in from Wallet before connecting a station.',
        404 || 501 => 'Ambient onboarding is unavailable on this server.',
        409 =>
          'This station is already registered. No ownership change was made.',
        422 => 'Station details or account ownership were rejected.',
        429 => 'Too many requests. Try again later.',
        _ => 'Could not contact the station service. Try again.',
      });
    } catch (_) {
      throw const AmbientOnboardingProblem(
        'Could not contact the station service. Try again.',
      );
    }
  }

  Future<VerifiedAmbientAccount> verify({
    required String apiKey,
    required String appKey,
    CancelToken? cancel,
  }) async {
    final key = apiKey.trim();
    final app = appKey.trim();
    if (key.isEmpty || app.isEmpty || key.length > 512 || app.length > 512) {
      throw const AmbientOnboardingProblem(
        'Enter both Ambient keys (up to 512 characters each).',
      );
    }
    final payload = await _post('/weather/stations/verify-key', {
      'provider': 'ambient',
      'apiKey': key,
      'appKey': app,
    }, cancel);
    if (payload['valid'] != true) {
      throw const AmbientOnboardingProblem(
        'No verified Ambient devices found. Check your account and keys.',
      );
    }
    final rows = payload['devices'];
    if (rows is! List || rows.length > 100) {
      throw const AmbientOnboardingProblem(
        'The station service returned an incomplete device list.',
      );
    }
    final seen = <String>{};
    final devices = <AmbientDevice>[];
    for (final row in rows) {
      final raw = row is Map ? row['mac'] : null;
      final mac =
          raw is String &&
              RegExp(
                r'^(?:[0-9a-f]{12}|(?:[0-9a-f]{2}:){5}[0-9a-f]{2}|(?:[0-9a-f]{2}-){5}[0-9a-f]{2})$',
                caseSensitive: false,
              ).hasMatch(raw.trim())
          ? raw.trim().toLowerCase().replaceAll(RegExp('[:-]'), '')
          : null;
      if (mac == null || !seen.add(mac)) {
        throw const AmbientOnboardingProblem(
          'The station service returned an incomplete device list.',
        );
      }
      // Names, fine coordinates and other vendor fields are not retained.
      devices.add(AmbientDevice._(mac));
    }
    return VerifiedAmbientAccount._(key, app, devices);
  }

  Future<String> register({
    required VerifiedAmbientAccount account,
    required AmbientDevice device,
    required String name,
    required double latitude,
    required double longitude,
    CancelToken? cancel,
  }) async {
    if (!account.devices.contains(device)) {
      throw const AmbientOnboardingProblem(
        'Select a device from the verified account.',
      );
    }
    if (name.trim().isEmpty ||
        name.trim().length > 80 ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw const AmbientOnboardingProblem(
        'Enter a station name and valid latitude/longitude.',
      );
    }
    final cell = CoarseLocation.round(latitude, longitude);
    final payload = await _post('/weather/stations', {
      'provider': 'ambient',
      'mac': device._mac,
      'name': name.trim(),
      'latitude': cell.latitude,
      'longitude': cell.longitude,
      'ambientApiKey': account._apiKey,
      'ambientAppKey': account._appKey,
    }, cancel);
    final id = payload['stationId'];
    if (payload['success'] != true ||
        payload['provider'] != 'ambient' ||
        id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id)) {
      throw const AmbientOnboardingProblem(
        'Registration was not confirmed by the station service.',
      );
    }
    return id;
  }
}
