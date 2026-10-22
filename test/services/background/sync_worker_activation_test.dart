import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/mobile_station_status_service.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registration_service.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/fake_station_backend.dart';

const awaiting =
    'Station awaiting activation. Rewards start once the network activates your station.';

class _Online implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _Db extends AppDatabase {
  _Db() : super(NativeDatabase.memory());
  @override
  Future<void> close() async {}
  Future<void> dispose() => super.close();
}

class _Wallet extends WalletSecureStorage {
  @override
  Future<String?> getWalletAddress() async => syntheticAddress;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Db db;
  late FakeStationBackend backend;
  late CollectKeyStore keys;
  late DateTime clock;
  late String phase;
  late int gets;
  late int delays;
  late String responseStation;
  late bool statusOffline;
  late bool statusNotRegistered;
  late bool inactivePrepare;
  late SyntheticSigner signer;

  Future<void> seed() => db.insertReading(
    SensorReadingsCompanion.insert(
      latitude: 1,
      longitude: 2,
      pressureHpa: 1000,
      timestamp: clock,
    ),
  );
  SyncWorker worker({bool foreground = false}) => SyncWorker(
    connectivity: _Online(),
    walletSecureStorage: _Wallet(),
    dbFactory: () => db,
    now: () => clock,
    delay: (_) async {
      delays++;
    },
    collectKeyStore: keys,
    canStartLogin: foreground,
    sessionOpener: signer.open,
    repositoryFactory: (database) {
      final dio = backend.buildDio();
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.method == 'GET' && o.path == '/weather/stations/mobile') {
              gets++;
              expect(o.queryParameters, isEmpty);
              expect(o.data, isNull);
              if (statusOffline) {
                h.reject(
                  DioException(
                    requestOptions: o,
                    type: DioExceptionType.connectionError,
                  ),
                );
              } else if (statusNotRegistered) {
                final response = Response<dynamic>(
                  requestOptions: o,
                  statusCode: 404,
                  data: {
                    'error': {'code': 'NOT_REGISTERED'},
                  },
                );
                h.reject(
                  DioException.badResponse(
                    statusCode: 404,
                    requestOptions: o,
                    response: response,
                  ),
                );
              } else {
                h.resolve(
                  Response<dynamic>(
                    requestOptions: o,
                    statusCode: 200,
                    data: {'stationId': responseStation, 'status': phase},
                  ),
                );
              }
              return;
            }
            if (o.method == 'POST' && o.path == '/weather/stations/mobile') {
              // A completed registration is what the server answers from.
              statusNotRegistered = false;
            }
            if (inactivePrepare && o.path == '/oracle/submit-data/prepare') {
              backend.requests.add(
                RecordedRequest(
                  o.path,
                  Map<String, dynamic>.from(o.data as Map),
                ),
              );
              final response = Response<dynamic>(
                requestOptions: o,
                statusCode: 409,
                data: {
                  'error': {'code': 'STATION_NOT_ACTIVE'},
                },
              );
              h.reject(
                DioException.badResponse(
                  statusCode: 409,
                  requestOptions: o,
                  response: response,
                ),
              );
              return;
            }
            h.next(o);
          },
        ),
      );
      final api = ApiClient(dio: dio, allowUnauthenticatedRequests: true);
      return CollectorRepository(
        sensorDataSource: SensorDataSource(LocationService()),
        batteryMonitor: BatteryMonitor(),
        apiClient: api,
        db: database,
        registration: StationRegistrationService(
          apiClient: api,
          now: () => clock,
        ),
      );
    },
  );
  setUp(() async {
    db = _Db();
    backend = FakeStationBackend()..registered = true;
    keys = syntheticCollectStore();
    signer = SyntheticSigner();
    SharedPreferences.setMockInitialValues(await registeredPrefsFor(keys));
    backend.collectPubkey = (await keys.load(syntheticAddress))!.publicKeyHex;
    clock = DateTime.utc(2026, 9, 30, 8);
    backend.nowSeconds = clock.millisecondsSinceEpoch ~/ 1000;
    phase = 'on_chain';
    gets = 0;
    delays = 0;
    responseStation = syntheticStationId;
    statusOffline = false;
    statusNotRegistered = false;
    inactivePrepare = false;
  });

  group('a reset that forgot this phone', () {
    // The backend (or the chain behind it) was reset: the server answers
    // NOT_REGISTERED while this phone still carries its v2 marker.
    test(
      'a foreground run re-registers and then waits for activation',
      () async {
        statusNotRegistered = true;
        phase = 'db_only';
        await seed();
        final result = await worker(foreground: true).syncPendingReadings();
        expect(backend.count('/weather/stations/mobile/challenge'), 1);
        expect(backend.count('/weather/stations/mobile'), 1);
        expect(backend.count('/oracle/submit-data/prepare'), 0);
        expect(result.message, awaiting);
        expect(result.acceptedCount, 0);
        expect(gets, 2);
        final key = (await keys.load(syntheticAddress))!;
        expect(
          await StationRegistrationService(
            apiClient: ApiClient(
              dio: backend.buildDio(),
              allowUnauthenticatedRequests: true,
            ),
            now: () => clock,
          ).isRegistered(syntheticStationId, key.publicKeyHex),
          isTrue,
        );
      },
    );

    test(
      'a background run cannot re-register: one check, no request',
      () async {
        statusNotRegistered = true;
        await seed();
        final result = await worker(foreground: false).syncPendingReadings();
        expect(backend.count('/weather/stations/mobile/challenge'), 0);
        expect(backend.count('/weather/stations/mobile'), 0);
        expect(result.acceptedCount, 0);
        expect(result.pendingCount, 1);
        expect(gets, 1);
      },
    );

    test('a registered phone still makes exactly one status check', () async {
      phase = 'on_chain';
      await seed();
      await worker(foreground: true).syncPendingReadings();
      expect(backend.count('/weather/stations/mobile'), 0);
      expect(backend.count('/oracle/submit-data'), 1);
      expect(gets, 1);
    });
  });
  tearDown(() async => db.dispose());
  for (final pending in ['db_only', 'submitted']) {
    for (final foreground in [true, false]) {
      test(
        '$pending => zero uploads, visible drops, bounded check (foreground=$foreground)',
        () async {
          phase = pending;
          await seed();
          final result = await worker(foreground: foreground)
              .syncPendingReadings();
          expect(backend.count('/oracle/submit-data/prepare'), 0);
          expect(backend.count('/oracle/submit-data'), 0);
          expect(result.acceptedCount, 0);
          expect(result.failedCount, 0);
          expect(result.message, awaiting);
          expect(result.pendingCount, 0);
          expect(result.droppedStaleCount, 1);
          expect(
            (await db.getSyncMetadata(staleReadingsNoticeTableName))
                ?.pendingCount,
            1,
          );
          expect(gets, 1);
          expect(delays, 0);
          await seed();
          await worker(foreground: foreground).syncPendingReadings();
          expect(gets, 2);
          expect(delays, 0);
          expect(backend.count('/oracle/submit-data/prepare'), 0);
        },
      );
    }
  }
  test('first registration still waits for activation', () async {
    SharedPreferences.setMockInitialValues({});
    phase = 'db_only';
    await seed();
    final result = await worker(foreground: true).syncPendingReadings();
    expect(backend.count('/weather/stations/mobile'), 1);
    expect(backend.count('/oracle/submit-data/prepare'), 0);
    expect(result.message, awaiting);
  });
  test('activation drops queued preconfirmation samples, then later readings upload', () async {
    phase = 'submitted';
    await seed();
    await worker().syncPendingReadings();
    clock = clock.add(const Duration(minutes: 10));
    await seed();
    phase = 'on_chain';
    final active = await worker().syncPendingReadings();
    expect(active.acceptedCount, 0);
    expect(backend.count('/oracle/submit-data/prepare'), 0);
    expect(
      (await db.getSyncMetadata(staleReadingsNoticeTableName))?.pendingCount,
      2,
    );
    clock = clock.add(const Duration(minutes: 1));
    await seed();
    final next = await worker().syncPendingReadings();
    expect(next.acceptedCount, 1);
    expect(backend.count('/oracle/submit-data/prepare'), 1);
    expect(gets, 3);
    expect(delays, 0);
  });
  test(
    'future-dated pending readings are discarded with a notice too',
    () async {
      phase = 'db_only';
      await db.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 1,
          longitude: 2,
          pressureHpa: 1000,
          timestamp: clock.add(const Duration(hours: 2)),
        ),
      );
      final result = await worker().syncPendingReadings();
      expect(result.pendingCount, 0);
      expect(result.droppedStaleCount, 1);
      expect(backend.count('/oracle/submit-data/prepare'), 0);
    },
  );
  test('verified active station uploads normally', () async {
    await seed();
    final result = await worker().syncPendingReadings();
    expect(gets, 1);
    expect(result.acceptedCount, 1);
    expect(result.droppedStaleCount, 0);
  });
  for (final kind in ['offline', 'foreign', 'malformed']) {
    test(
      '$kind status cannot authorize uploads, including cached on_chain',
      () async {
        await db.upsertOfflineData(
          MobileStationStatusService.cacheKey(syntheticStationId),
          jsonEncode({'stationId': syntheticStationId, 'status': 'on_chain'}),
        );
        statusOffline = kind == 'offline';
        if (kind == 'foreign') responseStation = 'mob-other';
        if (kind == 'malformed') phase = 'active';
        await seed();
        final result = await worker().syncPendingReadings();
        expect(backend.count('/oracle/submit-data/prepare'), 0);
        expect(result.acceptedCount, 0);
        expect(
          result.pendingCount,
          1,
          reason: 'uncertain status preserves data',
        );
        expect(gets, 1);
        expect(delays, 0);
      },
    );
  }
  test(
    'resume checks an empty queue and activates without a wallet prompt',
    () async {
      phase = 'db_only';
      final pending = await worker(foreground: true).syncOnResume();
      expect(pending.message, awaiting);
      expect(gets, 1);
      phase = 'on_chain';
      await worker(foreground: true).syncOnResume();
      expect(gets, 2);
      expect(signer.openAttempts, 0);
      await seed();
      final result = await worker().syncPendingReadings();
      expect(result.acceptedCount, 1);
    },
  );
  test(
    'resume never attempts registration when the collect key is missing',
    () async {
      keys = syntheticCollectStore();
      SharedPreferences.setMockInitialValues({});
      await seed();
      final result = await worker(foreground: true).syncOnResume();
      expect(result.acceptedCount, 0);
      expect(gets, 1);
      expect(signer.openAttempts, 0);
      expect(backend.count('/weather/stations/mobile'), 0);
      expect(backend.count('/oracle/submit-data/prepare'), 0);
    },
  );
  test('new worker instances retain the activation hold across runs', () async {
    phase = 'db_only';
    await seed();
    await worker().syncPendingReadings();
    phase = 'on_chain';
    clock = clock.add(const Duration(minutes: 1));
    await seed();
    final resumed = await worker(foreground: true).syncOnResume();
    expect(resumed.acceptedCount, 0);
    expect(gets, 2);
    clock = clock.add(const Duration(minutes: 1));
    await seed();
    expect((await worker().syncPendingReadings()).acceptedCount, 1);
  });
  for (final prepare in [true, false]) {
    test(
      '409 STATION_NOT_ACTIVE at ${prepare ? 'prepare' : 'submit'} is awaiting, never retried',
      () async {
        inactivePrepare = prepare;
        if (!prepare) {
          backend.failSubmitStatus = 409;
          backend.failSubmitCode = 'STATION_NOT_ACTIVE';
        }
        await seed();
        await seed();
        final result = await worker().syncPendingReadings();
        expect(result.message, awaiting);
        expect(result.failedCount, 0);
        expect(result.acceptedCount, 0);
        expect(result.pendingCount, 0);
        expect(backend.count('/oracle/submit-data/prepare'), 1);
        expect(backend.count('/oracle/submit-data'), prepare ? 0 : 1);
        expect(delays, 0);
        expect(
          (await db.getSyncMetadata(staleReadingsNoticeTableName))
              ?.pendingCount,
          2,
        );
      },
    );
  }
}
