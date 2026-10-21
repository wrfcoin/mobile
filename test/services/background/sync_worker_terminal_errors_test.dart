import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registration_service.dart';

import '../../test_helpers/fake_station_backend.dart';

class _Online implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// The worker closes its db in `finally`; keep the in-memory db alive across
/// consecutive runs within one test.
class _KeepOpenDb extends AppDatabase {
  _KeepOpenDb() : super(NativeDatabase.memory());
  @override
  Future<void> close() async {}
}

class _Wallet extends WalletSecureStorage {
  const _Wallet();
  @override
  Future<String?> getWalletAddress() async => syntheticAddress;
}

typedef _Responder = Response<dynamic> Function(RequestOptions, int index);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int requests;
  late DateTime clock;
  late List<Duration> delays;
  late _Responder responder;
  late SyntheticSigner signer;
  late CollectKeyStore collectStore;
  late FakeStationBackend registrar;

  Response<dynamic> failure(
    RequestOptions o,
    int status, {
    String? code,
    Map<String, String>? headers,
    Object? body,
  }) {
    final response = Response<dynamic>(
      requestOptions: o,
      statusCode: status,
      data:
          body ??
          <String, dynamic>{
            'success': false,
            'error': <String, dynamic>{'code': code ?? 'X', 'message': 'nope'},
          },
      headers: Headers.fromMap({
        for (final e in (headers ?? const <String, String>{}).entries)
          e.key: [e.value],
      }),
    );
    throw DioException.badResponse(
      statusCode: status,
      requestOptions: o,
      response: response,
    );
  }

  Response<dynamic> ok(RequestOptions o) => Response<dynamic>(
    requestOptions: o,
    statusCode: 200,
    data: <String, dynamic>{
      'success': true,
      'submissionId': 's',
      'status': 'x',
    },
  );

  SyncWorker buildWorker() {
    return SyncWorker(
      connectivity: _Online(),
      walletSecureStorage: const _Wallet(),
      dbFactory: () => db,
      delay: (d) async => delays.add(d),
      now: () => clock,
      sessionOpener: signer.open,
      collectKeyStore: collectStore,
      repositoryFactory: (database) {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              // The prepare leg answers like the real backend; these tests
              // count and script the submit leg only.
              final prepared = answerPrepare(options);
              if (prepared != null) {
                handler.resolve(prepared);
                return;
              }
              if (options.path.startsWith('/weather/stations/mobile')) {
                // Re-registration after STATION_NOT_OWNED succeeds here.
                registrar.handle(options).then(handler.resolve);
                return;
              }
              requests++;
              try {
                handler.resolve(responder(options, requests));
              } on DioException catch (e) {
                handler.reject(e);
              }
            },
          ),
        );
        final apiClient = ApiClient(
          dio: dio,
          allowUnauthenticatedRequests: true,
        );
        return CollectorRepository(
          sensorDataSource: SensorDataSource(LocationService()),
          batteryMonitor: BatteryMonitor(),
          apiClient: apiClient,
          db: database,
          registration: StationRegistrationService(
            apiClient: apiClient,
            now: () => clock,
          ),
        );
      },
    );
  }

  Future<void> seed(int n, {DateTime? at}) async {
    for (var i = 0; i < n; i++) {
      await db.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 10.0 + i,
          longitude: 20.0,
          pressureHpa: 1000.0 + i,
          timestamp: (at ?? DateTime.utc(2026, 9, 29, 12)).add(
            Duration(minutes: i),
          ),
        ),
      );
    }
  }

  setUp(() async {
    // Already registered: these tests are about the submit leg.
    collectStore = syntheticCollectStore();
    SharedPreferences.setMockInitialValues(
      await registeredPrefsFor(collectStore),
    );
    signer = SyntheticSigner();
    registrar = FakeStationBackend()..registered = true;
    db = _KeepOpenDb();
    requests = 0;
    delays = [];
    clock = DateTime.utc(2026, 9, 29, 12);
  });

  test(
    '403 STATION_NOT_OWNED: one request, readings pending, event reason',
    () async {
      await seed(5);
      responder = (o, i) => failure(o, 403, code: 'STATION_NOT_OWNED');
      final worker = buildWorker();

      final result = await worker.syncPendingReadings();

      // One re-registration attempt, then stop without resubmitting (design §6.2).
      expect(requests, 1);
      expect(result.reason, SyncRunReason.stationNotRegistered);
      expect(result.pendingCount, 5);
      expect(result.acceptedCount, 0);
      expect(
        delays,
        isEmpty,
        reason: 'terminal errors must not back off/retry',
      );
      expect(result.message, contains('readings are saved'));
    },
  );

  for (final entry in <int, String>{
    401: 'Sign in again',
    409: 'another owner',
    422: 'validation',
  }.entries) {
    test('${entry.key}: honest terminal state with queued readings', () async {
      await seed(3);
      responder = (o, i) => failure(
        o,
        entry.key,
        code: entry.key == 409 ? 'STATION_ID_TAKEN' : 'BAD',
      );
      final result = await buildWorker().syncPendingReadings();
      expect(result.pendingCount, 3);
      expect(result.message, contains(entry.value));
      expect(requests, 1);
      expect(delays, isEmpty);
    });
  }

  test('one502 ends the run without retrying a batch', () async {
    await seed(3);
    responder = (o, i) => failure(o, 502);
    final result = await buildWorker().syncPendingReadings();
    expect(requests, 1);
    expect(delays, isEmpty);
    expect(result.pendingCount, 3);
    expect(result.reason, SyncRunReason.failure);
  });
  test('mixed success then502 leaves only unfinished readings for the next user run', () async {
    await seed(4);
    responder = (o, i) => i == 1 ? ok(o) : failure(o, 502);
    final result = await buildWorker().syncPendingReadings();
    expect(requests, 2);
    expect(delays, isEmpty);
    expect(result.acceptedCount, 1);
    expect(result.pendingCount, 3);
    responder = (o, i) => ok(o);
    final next = await buildWorker().syncPendingReadings();
    expect(next.acceptedCount, 3);
    expect(requests, 5);
  });
  test(
    'confirmed replay readings leave the queue without an earned-credit claim',
    () async {
      await seed(3);
      responder = (o, i) => failure(o, 409, code: 'COMMIT_ALREADY_SUBMITTED');
      final result = await buildWorker().syncPendingReadings();
      expect(requests, 3);
      expect(delays, isEmpty);
      expect(result.pendingCount, 0);
      expect(result.acceptedCount, 0);
      expect(result.rewardTotalsAvailable, isFalse);
    },
  );

  test('400: one request, sync_rejected with status', () async {
    await seed(3);
    responder = (o, i) => failure(o, 400, code: 'BAD');

    final result = await buildWorker().syncPendingReadings();

    expect(requests, 1);
    expect(result.reason, SyncRunReason.rejected);
    expect(result.rejectedStatus, 400);
    expect(result.pendingCount, 3);
    expect(delays, isEmpty);
  });

  test('mixed batch: 3rd reading 403s -> requests stop at 3', () async {
    await seed(6);
    responder = (o, i) =>
        i < 3 ? ok(o) : failure(o, 403, code: 'STATION_NOT_OWNED');

    final result = await buildWorker().syncPendingReadings();

    // 3rd reading 403s -> one re-registration -> stop without retrying uploads.
    expect(requests, 3);
    expect(result.acceptedCount, 2);
    expect(result.pendingCount, 4);
    expect(result.reason, SyncRunReason.stationNotRegistered);
  });

  test(
    '429 Retry-After 120: stops, skips until due, then requests again',
    () async {
      await seed(4);
      responder = (o, i) => failure(o, 429, headers: {'retry-after': '120'});

      final first = await buildWorker().syncPendingReadings();
      expect(requests, 1);
      expect(first.reason, SyncRunReason.rateLimited);
      expect(first.pendingCount, 4);
      expect(delays, isEmpty);

      clock = clock.add(const Duration(seconds: 119));
      final skipped = await buildWorker().syncPendingReadings();
      expect(requests, 1, reason: 'no request inside the Retry-After window');
      expect(skipped.reason, SyncRunReason.rateLimited);

      clock = clock.add(const Duration(seconds: 2));
      responder = (o, i) => ok(o);
      final after = await buildWorker().syncPendingReadings();
      expect(requests, 5, reason: 'window elapsed: 4 readings submitted');
      expect(after.acceptedCount, 4);
      expect(after.pendingCount, 0);
    },
  );

  test('429 without Retry-After defaults to 15 minutes', () async {
    await seed(2);
    responder = (o, i) => failure(o, 429);
    await buildWorker().syncPendingReadings();

    clock = clock.add(const Duration(minutes: 14));
    await buildWorker().syncPendingReadings();
    expect(requests, 1);

    clock = clock.add(const Duration(minutes: 2));
    await buildWorker().syncPendingReadings();
    expect(requests, 2);
  });

  test('429 with an HTTP-date Retry-After is honoured', () async {
    await seed(2);
    responder = (o, i) => failure(
      o,
      429,
      headers: {'retry-after': 'Tue, 29 Sep 2026 12:05:00 GMT'},
    );
    await buildWorker().syncPendingReadings();

    clock = clock.add(const Duration(minutes: 4));
    await buildWorker().syncPendingReadings();
    expect(requests, 1);

    clock = clock.add(const Duration(minutes: 2));
    await buildWorker().syncPendingReadings();
    expect(requests, 2);
  });

  test('403 with the backend verbatim STATION_NOT_OWNED body', () async {
    await seed(2);
    responder = (o, i) => failure(
      o,
      403,
      body: jsonDecode(
        '{"success":false,"error":{"code":"STATION_NOT_OWNED","message":'
        '"Forbidden: this station is not registered to your wallet"},'
        '"timestamp":"2026-09-29T17:10:00.000Z"}',
      ),
    );

    final result = await buildWorker().syncPendingReadings();

    expect(requests, 1);
    expect(result.reason, SyncRunReason.stationNotRegistered);
    expect(result.pendingCount, 2);
  });

  test(
    '401 reaching the repository is terminal: one request, no retry',
    () async {
      await seed(3);
      responder = (o, i) => failure(o, 401, code: 'UNAUTHORIZED');

      final result = await buildWorker().syncPendingReadings();

      expect(requests, 1);
      expect(result.reason, SyncRunReason.rejected);
      expect(result.rejectedStatus, 401);
      expect(result.pendingCount, 3);
      expect(delays, isEmpty);
    },
  );

  group('429 lock is bounded', () {
    Future<void> expectBounded(String? header) async {
      await seed(2);
      responder = (o, i) => failure(
        o,
        429,
        headers: header == null ? null : {'retry-after': header},
      );
      await buildWorker().syncPendingReadings();
      expect(requests, 1);

      clock = clock.add(
        SyncWorker.maxRateLimitBackoff + const Duration(seconds: 1),
      );
      // The queued readings aged out of the attester window meanwhile.
      await seed(1, at: clock);
      await buildWorker().syncPendingReadings();
      expect(requests, 2, reason: 'must not stay locked beyond the cap');
    }

    test(
      'huge seconds (beyond int64)',
      () => expectBounded('99999999999999999999'),
    );
    test(
      'huge seconds (near int64 max)',
      () => expectBounded('9223372036854775807'),
    );
    test('one year of seconds', () => expectBounded('31536000'));
    test(
      'far-future HTTP date',
      () => expectBounded('Fri, 31 Dec 9999 23:59:59 GMT'),
    );
    test('negative', () => expectBounded('-5'));
    test('garbage', () => expectBounded('soon-ish'));
    test('zero uses the default, not no lock', () async {
      await seed(2);
      responder = (o, i) => failure(o, 429, headers: {'retry-after': '0'});
      await buildWorker().syncPendingReadings();
      clock = clock.add(const Duration(minutes: 14));
      await buildWorker().syncPendingReadings();
      expect(requests, 1);
      clock = clock.add(const Duration(minutes: 2));
      await buildWorker().syncPendingReadings();
      expect(requests, 2);
    });

    test(
      'skewed clock: persisted time beyond now+cap is ignored and cleared',
      () async {
        await seed(2);
        final bad = clock.add(const Duration(days: 30)).millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues(<String, Object>{
          ...await registeredPrefsFor(collectStore),
          SyncWorker.nextAllowedAtKey: bad,
        });
        responder = (o, i) => ok(o);

        final result = await buildWorker().syncPendingReadings();

        expect(requests, 2);
        expect(result.pendingCount, 0);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(SyncWorker.nextAllowedAtKey), isNull);
      },
    );
  });

  test('rate-limit guard records the last sync attempt metadata', () async {
    await seed(2);
    responder = (o, i) => failure(o, 429, headers: {'retry-after': '120'});
    await buildWorker().syncPendingReadings();

    // Wipe metadata so only the pre-flight guard path can write it.
    await db.clearSyncMetadata(sensorReadingsSyncTableName);
    clock = clock.add(const Duration(seconds: 30));
    final skipped = await buildWorker().syncPendingReadings();

    expect(skipped.reason, SyncRunReason.rateLimited);
    final meta = await db.getSyncMetadata(sensorReadingsSyncTableName);
    expect(meta?.lastSyncAttemptAt, isNotNull);
    expect(meta?.lastSyncError, SyncWorker.rateLimitedMessage);
    expect(meta?.pendingCount, 2);
  });

  test('500 keeps the existing bounded backoff', () async {
    await seed(2);
    responder = (o, i) => failure(o, 500);

    final result = await buildWorker().syncPendingReadings();

    // Each failing batch submits every reading (2) and there are maxRetries
    // rounds, with backoff between them.
    expect(requests, SyncWorker.maxRetries * 2);
    expect(result.reason, SyncRunReason.failure);
    expect(delays, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
      const Duration(seconds: 8),
    ]);
    expect(result.pendingCount, 2);
  });
}
