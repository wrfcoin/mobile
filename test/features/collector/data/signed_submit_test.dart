import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fake_station_backend.dart';
import '../../../test_helpers/fakes.dart';

void main() {
  late FakeStationBackend backend;
  late FakeCollectorLocalStore store;
  late CollectKey session;

  CollectorRepository repo(Dio dio) => CollectorRepository(
    sensorDataSource: SensorDataSource(LocationService()),
    batteryMonitor: BatteryMonitor(),
    apiClient: ApiClient(dio: dio, allowUnauthenticatedRequests: true),
    db: store,
  );

  List<SensorReading> readings(int n) {
    store.pendingCount = n;
    return List.generate(
      n,
      (i) => SensorReading(
        id: i + 1,
        latitude: 37.7749,
        longitude: -122.4194,
        pressureHpa: 1013.25 + i,
        timestamp: DateTime.utc(2026, 9, 29, 11, i),
        synced: false,
      ),
    );
  }

  setUp(() async {
    backend = FakeStationBackend()..registered = true;
    store = FakeCollectorLocalStore();
    session = await syntheticCollectKey();
  });

  test('prepare, then a locally signed submit with the same body', () async {
    final result = await repo(backend.buildDio()).submitBatch(
      readings(2),
      walletAddress: syntheticAddress,
      signer: session,
    );

    expect(result.acceptedCount, 2);
    expect(backend.paths, [
      '/oracle/submit-data/prepare',
      '/oracle/submit-data',
      '/oracle/submit-data/prepare',
      '/oracle/submit-data',
    ]);
    final prepare = backend.requests[0].body;
    final submit = backend.requests[1].body;
    expect(prepare['stationId'], syntheticStationId);
    expect(prepare.containsKey('auth_signature'), isFalse);
    expect(submit['stationId'], syntheticStationId);
    expect(submit['nonce'], prepare['nonce']);
    expect(submit['auth_pubkey'], session.publicKeyHex);
    expect(submit['auth_signature'], hasLength(128));
    // Everything the server hashed is unchanged between the two calls.
    for (final k in ['dataType', 'value', 'timestamp', 'location', 'source']) {
      expect(submit[k], prepare[k], reason: k);
    }
    // The fake backend verified each signature over the locally built preimage.
    expect(backend.verifiedAuthSignatures, hasLength(2));
  });

  test(
    'a server commitHash that differs from the local one is refused',
    () async {
      backend.prepareCommitId = 'ab' * 32;
      final result = await repo(backend.buildDio()).submitBatch(
        readings(3),
        walletAddress: syntheticAddress,
        signer: session,
      );

      expect(result.refusal, SubmitRefusal.commitHashMismatch);
      expect(result.acceptedCount, 0);
      expect(
        backend.count('/oracle/submit-data'),
        0,
        reason: 'nothing signed/sent',
      );
      expect(
        backend.count('/prepare'),
        1,
        reason: 'batch aborts at the first refusal',
      );
      expect(store.syncedIds, isEmpty);
    },
  );

  test(
    'a server messageHex that differs from the local preimage is refused',
    () async {
      backend.prepareMessageHex = 'deadbeef';
      final result = await repo(backend.buildDio()).submitBatch(
        readings(1),
        walletAddress: syntheticAddress,
        signer: session,
      );

      expect(result.refusal, SubmitRefusal.authorizationMismatch);
      expect(backend.count('/oracle/submit-data'), 0);
    },
  );

  group('the phone cross-checks every field the server echoes', () {
    for (final c in <(String, void Function(FakeStationBackend))>[
      ('stationId', (b) => b.prepareStationId = 'mob-${'2' * 32}'),
      ('timestamp', (b) => b.prepareTimestamp = 1),
      (
        'authorization.commitId',
        (b) => b.prepareAuthorizationCommitId = 'ef' * 32,
      ),
    ]) {
      test('a wrong echoed ${c.$1} is refused and nothing is signed', () async {
        c.$2(backend);
        final result = await repo(backend.buildDio()).submitBatch(
          readings(2),
          walletAddress: syntheticAddress,
          signer: session,
        );

        expect(result.refusal, SubmitRefusal.authorizationMismatch);
        expect(result.acceptedCount, 0);
        expect(backend.count('/oracle/submit-data'), 0);
        expect(backend.verifiedAuthSignatures, isEmpty);
      });
    }
  });

  group('deterministic nonce', () {
    Future<List<Map<String, dynamic>>> submitBodies(
      List<SensorReading> rs,
    ) async {
      final b = FakeStationBackend()..registered = true;
      await repo(b.buildDio())
          .submitBatch(rs, walletAddress: syntheticAddress, signer: session);
      return [
        for (final r in b.requests)
          if (r.path == '/oracle/submit-data') r.body,
      ];
    }

    test('a retry of the same reading commits the same nonce and id', () async {
      final rs = readings(1);
      final first = (await submitBodies(rs)).single;
      final retry = (await submitBodies(rs)).single;

      expect(retry['nonce'], first['nonce']);
      // Ed25519 is deterministic: equal signatures mean an equal commit id.
      expect(retry['auth_signature'], first['auth_signature']);
    });

    test('two different readings never share a nonce or commit id', () async {
      final bodies = await submitBodies(readings(2));

      expect(bodies[0]['nonce'], isNot(bodies[1]['nonce']));
      expect(bodies[0]['auth_signature'], isNot(bodies[1]['auth_signature']));
    });
  });

  test(
    'long pressure is quantized identically on prepare and submit',
    () async {
      final rs = readings(1);
      final reading = SensorReading(
        id: rs[0].id,
        latitude: 10,
        longitude: 20,
        pressureHpa: 1008.2767333984375,
        timestamp: rs[0].timestamp,
        synced: false,
      );
      final result = await repo(backend.buildDio()).submitBatch(
        [reading],
        walletAddress: syntheticAddress,
        signer: session,
      );
      expect(result.acceptedCount, 1);
      for (final r in backend.requests) {
        expect(r.body['value'], 1008.28);
      }
    },
  );
  for (final value in [1008.004, -0.0, -0.004]) {
    test('wire JSON prints quantized $value like JS', () async {
      final original = readings(1).single;
      final reading = SensorReading(
        id: original.id,
        latitude: original.latitude,
        longitude: original.longitude,
        pressureHpa: value,
        timestamp: original.timestamp,
        synced: false,
      );
      final result = await repo(backend.buildDio()).submitBatch(
        [reading],
        walletAddress: syntheticAddress,
        signer: session,
      );
      expect(result.acceptedCount, 1);
      for (final request in backend.requests) {
        expect(jsonEncode(request.body['value']), value > 0 ? '1008' : '0');
      }
    });
  }
  for (final atPrepare in [true, false]) {
    test(
      'COMMIT_ALREADY_SUBMITTED at ${atPrepare ? 'prepare' : 'submit'} completes that reading without claiming rewards',
      () async {
        final dio = backend.buildDio();
        dio.interceptors.insert(
          0,
          InterceptorsWrapper(
            onRequest: (o, h) {
              if (o.path ==
                  (atPrepare
                      ? '/oracle/submit-data/prepare'
                      : '/oracle/submit-data')) {
                final response = Response<dynamic>(
                  requestOptions: o,
                  statusCode: 409,
                  data: {
                    'error': {'code': 'COMMIT_ALREADY_SUBMITTED'},
                  },
                );
                h.reject(
                  DioException.badResponse(
                    statusCode: 409,
                    requestOptions: o,
                    response: response,
                  ),
                );
              } else {
                h.next(o);
              }
            },
          ),
        );
        final result = await repo(dio).submitBatch(
          readings(3),
          walletAddress: syntheticAddress,
          signer: session,
        );
        expect(store.syncedIds, [1, 2, 3]);
        expect(store.pendingCount, 0);
        expect(result.failedCount, 0);
        expect(result.acceptedCount, 0);
        expect(result.rewardTotalsAvailable, isFalse);
        expect(result.rewardWrfTotal, 0);
      },
    );
  }
  test('one502 stops the remaining batch immediately', () async {
    backend.failSubmitStatus = 502;
    final result = await repo(backend.buildDio()).submitBatch(
      readings(4),
      walletAddress: syntheticAddress,
      signer: session,
    );
    expect(backend.count('/oracle/submit-data'), 1);
    expect(backend.count('/prepare'), 1);
    expect(result.failedCount, 4);
    expect(store.pendingCount, 4);
  });

  test('429 still stops the batch with Retry-After (#337 semantics)', () async {
    backend.failSubmitStatus = 429;
    backend.failSubmitHeaders = {'retry-after': '90'};
    final result = await repo(backend.buildDio()).submitBatch(
      readings(4),
      walletAddress: syntheticAddress,
      signer: session,
    );

    expect(result.failure?.isRateLimited, isTrue);
    expect(backend.count('/oracle/submit-data'), 1);
    expect(backend.count('/prepare'), 1);
  });
}
