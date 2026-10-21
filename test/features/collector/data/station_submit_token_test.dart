import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_submit_token_store.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../../test_helpers/fakes.dart';

final station = 'mob-${'a' * 32}';
final otherStation = 'mob-${'b' * 32}';
final credential = 'c' * 64; // synthetic, never an operator credential
String packet([String? id, String? token]) =>
    jsonEncode({'stationId': id ?? station, 'token': token ?? credential});

class WireAdapter implements HttpClientAdapter {
  int calls = 0;
  int status = 200;
  String? authorization;
  Map<String, dynamic>? extra;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    authorization = options.headers['Authorization'] as String?;
    extra = Map.of(options.extra);
    return ResponseBody.fromString(
      '{}',
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'import binds packet to one station and remove leaves collect key',
    () async {
      final storage = InMemoryKeyValueStorage();
      await storage.write(key: 'collect_key_seed', value: 'synthetic-seed');
      final store = StationSubmitTokenStore(storage: storage);
      await store.importPacket(station, packet());
      expect(await store.read(station), credential);
      expect(await store.read(otherStation), isNull);
      await store.remove(station);
      expect(await store.read(station), isNull);
      expect(await storage.read(key: 'collect_key_seed'), 'synthetic-seed');
    },
  );

  test(
    'wrong station, malformed/empty/padded credential and web storage refuse',
    () async {
      final store = StationSubmitTokenStore(storage: InMemoryKeyValueStorage());
      for (final input in [
        packet(otherStation),
        'invalid-json',
        packet(station, ''),
        packet(station, '$credential\n'),
        packet(station, ' $credential'),
        packet(station, 'z' * 64),
      ]) {
        await expectLater(
          store.importPacket(station, input),
          throwsFormatException,
        );
        expect(await store.read(station), isNull);
      }
      final web = StationSubmitTokenStore(
        storage: InMemoryKeyValueStorage(),
        native: false,
      );
      await expectLater(web.importPacket(station, packet()), throwsStateError);
      await expectLater(web.read(station), throwsStateError);
    },
  );

  test(
    'Emergency Wipe of collect namespace also erases submit credential',
    () async {
      final storage = InMemoryKeyValueStorage();
      final store = StationSubmitTokenStore(storage: storage);
      await store.importPacket(station, packet());
      await CollectKeyStore(storage: storage).wipe();
      expect(await store.read(station), isNull);
    },
  );

  test(
    'corrupt stored credential refuses without echoing stored value',
    () async {
      final storage = InMemoryKeyValueStorage();
      await storage.write(
        key: 'weather_submit_token:$station',
        value: 'corrupt-synthetic',
      );
      final store = StationSubmitTokenStore(storage: storage);
      await expectLater(store.read(station), throwsStateError);
    },
  );

  Future<(ApiClient, WireAdapter, KeyManager)> client() async {
    final store = StationSubmitTokenStore(storage: InMemoryKeyValueStorage());
    await store.importPacket(station, packet());
    final manager = KeyManager(
      biometric: BiometricService(
        client: FakeLocalAuthClient(authenticateResult: true),
      ),
      storage: InMemoryKeyValueStorage(),
    );
    await manager.storeAuthSession(
      jwt: 'synthetic-account-jwt',
      expiresInSeconds: 3600,
    );
    final api = ApiClient(keyManager: manager, stationSubmitTokens: store);
    api.dio.options.baseUrl = 'https://weather.invalid/api';
    final adapter = WireAdapter();
    api.dio.httpClientAdapter = adapter;
    addTearDown(() => api.dio.close(force: true));
    return (api, adapter, manager);
  }

  test(
    'production ApiClient sends station Bearer and signed oracle keeps JWT',
    () async {
      final (api, wire, _) = await client();
      await api.dio.post('/weather/submit', data: {'stationId': station});
      expect(wire.authorization, 'Bearer $credential');
      expect(wire.extra?['noRetry'], isTrue);
      await api.dio.post('/oracle/submit-data', data: {'stationId': station});
      expect(wire.authorization, 'Bearer synthetic-account-jwt');
    },
  );

  test(
    'snake_case station selector supported; ambiguous selector refuses',
    () async {
      final (api, wire, _) = await client();
      await api.dio.post('/weather/submit', data: {'station_id': station});
      expect(wire.authorization, 'Bearer $credential');
      await expectLater(
        api.dio.post(
          '/weather/submit',
          data: {'stationId': station, 'station_id': otherStation},
        ),
        throwsA(isA<DioException>()),
      );
      expect(wire.calls, 1);
    },
  );

  test(
    'unknown station and missing body fail locally, no anonymous fallback',
    () async {
      final (api, wire, _) = await client();
      for (final body in [
        null,
        {'stationId': otherStation},
        {'stationId': ''},
      ]) {
        await expectLater(
          api.dio.post('/weather/submit', data: body),
          throwsA(isA<DioException>()),
        );
      }
      expect(wire.calls, 0);
    },
  );

  test(
    'station token never reaches another origin, GET, or lookalike path',
    () async {
      final (api, wire, _) = await client();
      for (final path in [
        'https://other.invalid/api/weather/submit',
        '/weather/submit/other',
      ]) {
        await api.dio.post(path, data: {'stationId': station});
        expect(wire.authorization, isNot('Bearer $credential'));
      }
      await api.dio.get('/weather/submit');
      expect(wire.authorization, isNot('Bearer $credential'));
      api.dio.options.baseUrl = 'http://weather.invalid/api';
      final before = wire.calls;
      await expectLater(
        api.dio.post('/weather/submit', data: {'stationId': station}),
        throwsA(isA<DioException>()),
      );
      expect(wire.calls, before);
    },
  );

  test('401 station refusal neither refreshes JWT nor replays; token removed from error', () async {
    final (api, wire, manager) = await client();
    wire.status = 401;
    try {
      await api.dio.post('/weather/submit', data: {'stationId': station});
      fail('expected station credential refusal');
    } on DioException catch (error) {
      expect(
        error.requestOptions.headers.containsKey('Authorization'),
        isFalse,
      );
      expect(error.toString().contains(credential), isFalse);
    }
    expect(wire.calls, 1);
    expect(await manager.getAuthToken(), 'synthetic-account-jwt');
  });
}
