import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart'
    show Variable, ResultSetImplementation, UpdateKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/mobile_station_status_service.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fake_station_backend.dart';

void main() {
  late AppDatabase db;
  late RequestOptions lastRequest;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });

  MobileStationStatusService service(Object? body, {int status = 200}) {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            lastRequest = o;
            expect(o.method, 'GET');
            expect(o.path, '/weather/stations/mobile');
            expect(o.queryParameters, isEmpty);
            expect(o.data, isNull);
            final response = Response<dynamic>(
              requestOptions: o,
              data: body,
              statusCode: status,
            );
            if (status >= 400) {
              h.reject(
                DioException.badResponse(
                  statusCode: status,
                  requestOptions: o,
                  response: response,
                ),
              );
            } else {
              h.resolve(response);
            }
          },
        ),
      );
    return MobileStationStatusService(
      apiClient: ApiClient(dio: dio),
      db: db,
    );
  }

  test(
    'status request contains neither coordinates nor any query or body',
    () async {
      await service({'stationId': syntheticStationId, 'status': 'submitted'})
          .fetch(syntheticAddress);
      expect(lastRequest.method, 'GET');
      expect(lastRequest.path, '/weather/stations/mobile');
      expect(lastRequest.queryParameters, isEmpty);
      expect(lastRequest.data, isNull);
    },
  );

  test('verified station status is cached under the derived id', () async {
    final result = await service({
      'stationId': syntheticStationId,
      'status': 'submitted',
    }).fetch(syntheticAddress);
    expect(result.phase, MobileStationPhase.submitted);
    expect(result.cached, false);
    final cached = await db.getOfflineData(
      MobileStationStatusService.cacheKey(syntheticStationId),
    );
    expect(jsonDecode(cached!.payload)['status'], 'submitted');
  });

  for (final body in [
    {'stationId': 'mob-someone-else', 'status': 'on_chain'},
    {'stationId': syntheticStationId, 'status': 'invented'},
    {'stationId': syntheticStationId, 'status': 'none'},
    null,
  ]) {
    test(
      'malformed or foreign status never claims activation: $body',
      () async {
        final result = await service(body).fetch(syntheticAddress);
        expect(result.phase, MobileStationPhase.unknown);
        expect(
          await db.getOfflineData(
            MobileStationStatusService.cacheKey(syntheticStationId),
          ),
          isNull,
        );
      },
    );
  }

  test('404 NOT_REGISTERED clears cached activation', () async {
    await service({'stationId': syntheticStationId, 'status': 'on_chain'})
        .fetch(syntheticAddress);
    final result = await service({
      'error': {'code': 'NOT_REGISTERED'},
    }, status: 404).fetch(syntheticAddress);
    expect(result.phase, MobileStationPhase.none);
    expect(result.cached, false);
  });

  for (final status in [401, 403, 404, 429, 503]) {
    test(
      '$status without NOT_REGISTERED is unknown, never unregistered or active',
      () async {
        final result = await service({
          'error': {'code': 'X'},
        }, status: status).fetch(syntheticAddress);
        expect(result.phase, MobileStationPhase.unknown);
      },
    );
  }

  test('a failed refresh marks cached activation as unconfirmed', () async {
    await service({'stationId': syntheticStationId, 'status': 'on_chain'})
        .fetch(syntheticAddress);
    final result = await service(null, status: 503).fetch(syntheticAddress);
    expect(result.phase, MobileStationPhase.onChain);
    expect(result.cached, true);
    expect(result.message, contains('rewards are not confirmed'));
  });

  test('another wallet cannot inherit a cached station status', () async {
    await service({'stationId': syntheticStationId, 'status': 'on_chain'})
        .fetch(syntheticAddress);
    final result = await service(null, status: 503).fetch('0x${'12' * 20}');
    expect(result.phase, MobileStationPhase.unknown);
  });

  test(
    'drop increments the database count despite a stale client observation',
    () async {
      final stale = _StaleObservationDb();
      addTearDown(stale.close);
      await stale.upsertSyncMetadata(
        syncTableName: staleReadingsNoticeTableName,
        pendingCount: 5,
      );
      await stale.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 1,
          longitude: 2,
          pressureHpa: 1000,
          timestamp: DateTime.utc(2026, 9, 29),
        ),
      );
      stale.returnStaleCount = true;
      expect(
        await stale.dropStaleReadingsWithNotice(DateTime.utc(2026, 9, 30)),
        1,
      );
      // Read storage directly: the synthetic stale client must not decide the sum.
      final rows = await stale.select(stale.syncMetadataEntries).get();
      expect(rows.single.pendingCount, 6);
      expect(await stale.getPendingSyncCount(), 0);
    },
  );

  test('first drop creates one notice; subsequent drops add to it', () async {
    for (var i = 0; i < 3; i++) {
      await db.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 1,
          longitude: 2,
          pressureHpa: 1000,
          timestamp: DateTime.utc(2026, 9, 29),
        ),
      );
      expect(
        await db.dropStaleReadingsWithNotice(DateTime.utc(2026, 9, 30)),
        1,
      );
    }
    final rows = await db.select(db.syncMetadataEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.pendingCount, 3);
    expect(await db.dropStaleReadingsWithNotice(DateTime.utc(2026, 9, 30)), 0);
    expect(
      (await db.getSyncMetadata(staleReadingsNoticeTableName))!.pendingCount,
      3,
    );
  });

  test(
    'notice persistence failure rolls back stale-reading deletion',
    () async {
      final failing = _NoticeFailureDb();
      addTearDown(failing.close);
      await failing.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 1,
          longitude: 2,
          pressureHpa: 1000,
          timestamp: DateTime.utc(2026, 9, 29),
        ),
      );
      await expectLater(
        failing.dropStaleReadingsWithNotice(DateTime.utc(2026, 9, 30)),
        throwsStateError,
      );
      expect(await failing.getPendingSyncCount(), 1);
    },
  );

  test(
    'acknowledging an old count retains newer background drop notices',
    () async {
      await db.upsertSyncMetadata(
        syncTableName: staleReadingsNoticeTableName,
        pendingCount: 5,
      );
      await db.acknowledgeStaleReadings(3);
      expect(
        (await db.getSyncMetadata(staleReadingsNoticeTableName))?.pendingCount,
        2,
      );
      await db.acknowledgeStaleReadings(2);
      expect(await db.getSyncMetadata(staleReadingsNoticeTableName), isNull);
    },
  );
}

class _NoticeFailureDb extends AppDatabase {
  _NoticeFailureDb() : super(NativeDatabase.memory());
  @override
  Future<int> customUpdate(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation>? updates,
    UpdateKind? updateKind,
  }) async {
    throw StateError('synthetic notice failure');
  }

  @override
  Future<void> upsertSyncMetadata({
    required String syncTableName,
    required int pendingCount,
    DateTime? lastSyncAt,
    DateTime? lastSyncAttemptAt,
    String? lastSyncError,
  }) async {
    if (syncTableName == staleReadingsNoticeTableName) {
      throw StateError('synthetic notice failure');
    }
    await super.upsertSyncMetadata(
      syncTableName: syncTableName,
      pendingCount: pendingCount,
      lastSyncAt: lastSyncAt,
      lastSyncAttemptAt: lastSyncAttemptAt,
      lastSyncError: lastSyncError,
    );
  }
}

// Models a cached/stale client observation, not an actual SQLite busy race.
class _StaleObservationDb extends AppDatabase {
  _StaleObservationDb() : super(NativeDatabase.memory());
  bool returnStaleCount = false;
  @override
  Future<SyncMetadataEntry?> getSyncMetadata(String syncTableName) async {
    final stored = await super.getSyncMetadata(syncTableName);
    if (returnStaleCount && syncTableName == staleReadingsNoticeTableName) {
      return stored?.copyWith(pendingCount: 0);
    }
    return stored;
  }
}
