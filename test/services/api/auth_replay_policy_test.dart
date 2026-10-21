import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/ambient_onboarding_repository.dart';
import 'package:wrfcoin_mobile/features/weather/data/station_temperature_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../test_helpers/fakes.dart';

class _Transport implements HttpClientAdapter {
  _Transport(this.path, this.first, this.second);
  final String path;
  final Object first;
  final Object second;
  final List<String?> authorizations = [];
  int refreshes = 0;
  void Function()? onRefresh;

  ResponseBody json(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == ApiConstants.authRefresh) {
      refreshes++;
      onRefresh?.call();
      return json({'jwt': 'fresh-access', 'refreshToken': 'refresh'}, 200);
    }
    if (options.path == path) {
      authorizations.add(options.headers['Authorization'] as String?);
      final outcome = authorizations.length == 1 ? first : second;
      if (outcome is DioExceptionType) {
        throw DioException(requestOptions: options, type: outcome);
      }
      if (outcome != 200) return json({'error': 'synthetic'}, outcome as int);
    }
    return json(switch (options.path) {
      '/weather/stations/verify-key' => {
        'valid': true,
        'devices': [
          {'mac': '001122334455'},
        ],
      },
      '/weather/stations' => {
        'success': true,
        'provider': 'ambient',
        'stationId': 'synthetic-station',
      },
      _ => {'daily': <Object>[]},
    }, 200);
  }
}

Future<Future<Object> Function()> _operation(
  String action,
  _Transport transport, {
  CancelToken? cancel,
}) async {
  final storage = InMemoryKeyValueStorage();
  // No expiry field: the server rejection controls the synthetic session.
  await storage.write(key: 'wrf_jwt', value: 'cached-access');
  await storage.write(key: 'wrf_refresh_token', value: 'refresh');
  await storage.write(
    key: 'wrf_address',
    value: '0x2222222222222222222222222222222222222222',
  );
  final keys = KeyManager(
    biometric: BiometricService(client: FakeLocalAuthClient()),
    storage: storage,
  );
  final authDio = Dio()..httpClientAdapter = transport;
  final client = ApiClient(keyManager: keys, authDio: authDio);
  client.dio.options.baseUrl = 'https://auth-policy.invalid/api';
  authDio.options.baseUrl = client.dio.options.baseUrl;
  client.dio.httpClientAdapter = transport;
  addTearDown(() => client.dio.close(force: true));
  addTearDown(() => authDio.close(force: true));
  if (action == 'temperature') {
    return () =>
        StationTemperatureRemoteDataSource(client.dio)
            .fetch(CoarseLocation.round(10, 20), cancelToken: cancel);
  }
  final ambient = AmbientOnboardingRepository(client);
  if (action == 'verify') {
    return () => ambient.verify(
      apiKey: 'synthetic-api',
      appKey: 'synthetic-app',
      cancel: cancel,
    );
  }
  final account = await ambient.verify(
    apiKey: 'synthetic-api',
    appKey: 'synthetic-app',
  );
  return () => ambient.register(
    account: account,
    device: account.devices.single,
    name: 'Synthetic station',
    latitude: 10,
    longitude: 20,
    cancel: cancel,
  );
}

void main() {
  const paths = {
    'temperature': '/weather/temperature-history',
    'verify': '/weather/stations/verify-key',
    'register': '/weather/stations',
  };
  for (final entry in paths.entries) {
    for (final second in [
      200,
      401,
      503,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      test('${entry.key} refreshes once after 401, then $second', () async {
        final transport = _Transport(entry.value, 401, second);
        final submit = await _operation(entry.key, transport);
        if (second == 200) {
          final result = await submit();
          if (result is StationTemperatureFetch) {
            expect(result.kind, StationTemperatureFetchKind.data);
          } else if (entry.key == 'register') {
            expect(result, 'synthetic-station');
          } else {
            expect(result, isA<VerifiedAmbientAccount>());
          }
        } else if (entry.key == 'temperature') {
          final result = await submit() as StationTemperatureFetch;
          expect(result.kind, isNot(StationTemperatureFetchKind.data));
        } else {
          await expectLater(submit(), throwsA(isA<AmbientOnboardingProblem>()));
        }
        expect(transport.refreshes, 1);
        expect(transport.authorizations, [
          'Bearer cached-access',
          'Bearer fresh-access',
        ]);
      });
    }
    for (final first in [
      503,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      test('${entry.key} retains no transient retry after $first', () async {
        final transport = _Transport(entry.value, first, 200);
        final submit = await _operation(entry.key, transport);
        if (entry.key == 'temperature') {
          final result = await submit() as StationTemperatureFetch;
          expect(result.kind, StationTemperatureFetchKind.unavailable);
        } else {
          await expectLater(submit(), throwsA(isA<AmbientOnboardingProblem>()));
        }
        expect(transport.refreshes, 0);
        expect(transport.authorizations, ['Bearer cached-access']);
      });
    }
    test('${entry.key} cancellation during refresh prevents replay', () async {
      final cancel = CancelToken();
      final transport = _Transport(entry.value, 401, 200)
        ..onRefresh = () => cancel.cancel('synthetic cancellation');
      final submit = await _operation(entry.key, transport, cancel: cancel);
      if (entry.key == 'temperature') {
        final result = await submit() as StationTemperatureFetch;
        expect(result.kind, isNot(StationTemperatureFetchKind.data));
      } else {
        await expectLater(submit(), throwsA(isA<AmbientOnboardingProblem>()));
      }
      expect(transport.refreshes, 1);
      expect(transport.authorizations, ['Bearer cached-access']);
    });
  }
}
