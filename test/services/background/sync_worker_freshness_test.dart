import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registration_service.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/fake_station_backend.dart';

class _Connectivity implements Connectivity {
  bool online = true;
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    online ? ConnectivityResult.wifi : ConnectivityResult.none,
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

class _Backend extends FakeStationBackend {
  void Function(String)? afterResponse;
  @override
  Future<Response<dynamic>> handle(RequestOptions options) async {
    final response = await super.handle(options);
    afterResponse?.call(options.path);
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Db db;
  late _Backend backend;
  late _Connectivity connectivity;
  late CollectKeyStore keys;
  late DateTime clock;
  late SyntheticSigner walletSigner;
  void Function()? onRetry;

  setUp(() async {
    clock = DateTime.utc(2026, 9, 29, 12);
    db = _Db();
    backend = _Backend()..registered = true;
    connectivity = _Connectivity();
    keys = syntheticCollectStore();
    walletSigner = SyntheticSigner();
    SharedPreferences.setMockInitialValues(await registeredPrefsFor(keys));
    onRetry = null;
  });
  tearDown(() => db.dispose());

  Future<void> seed(Duration age, {int count = 1}) async {
    for (var i = 0; i < count; i++) {
      await db.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 10.1,
          longitude: 20.2,
          pressureHpa: 1013.25,
          timestamp: clock.subtract(age),
        ),
      );
    }
  }

  SyncWorker worker({bool foreground = false}) => SyncWorker(
    connectivity: connectivity,
    walletSecureStorage: _Wallet(),
    dbFactory: () => db,
    collectKeyStore: keys,
    now: () => clock,
    canStartLogin: foreground,
    sessionOpener: walletSigner.open,
    delay: (_) async => onRetry?.call(),
    repositoryFactory: (database) {
      final api = ApiClient(
        dio: backend.buildDio(),
        allowUnauthenticatedRequests: true,
      );
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

  Future<int> noticeCount() async =>
      (await db.getSyncMetadata(staleReadingsNoticeTableName))?.pendingCount ??
      0;

  test(
    'offline expiry leaves a durable notice and retains fresh rows',
    () async {
      await seed(const Duration(minutes: 55));
      await seed(const Duration(minutes: 49));
      connectivity.online = false;
      final result = await worker().syncPendingReadings();
      expect(result.reason, SyncRunReason.offline);
      expect(result.pendingCount, 1);
      expect(result.droppedStaleCount, 1);
      expect(result.notice, SyncWorker.staleReadingsNotice(1));
      expect(await noticeCount(), 1);
      expect(backend.requests, isEmpty);
      expect(backend.statusRequests, isEmpty);
      final again = await worker().syncPendingReadings();
      expect(again.droppedStaleCount, 0);
      expect(await noticeCount(), 1);
    },
  );

  test('backoff expiry does not send a request or claim an earning', () async {
    await seed(const Duration(minutes: 55));
    await seed(const Duration(minutes: 49));
    await (await SharedPreferences.getInstance()).setInt(
      SyncWorker.nextAllowedAtKey,
      clock.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
    );
    final result = await worker().syncPendingReadings();
    expect(result.reason, SyncRunReason.rateLimited);
    expect(result.pendingCount, 1);
    expect(result.droppedStaleCount, 1);
    expect(await noticeCount(), 1);
    expect(result.acceptedCount, 0);
    expect(result.rewardTotalsAvailable, isFalse);
    expect(backend.requests, isEmpty);
    expect(backend.statusRequests, isEmpty);
  });

  test('slow prepare ages out before any commit signature or submit', () async {
    await seed(const Duration(minutes: 49));
    backend.afterResponse = (path) {
      if (path.endsWith('/prepare')) {
        clock = clock.add(const Duration(minutes: 2));
      }
    };
    final result = await worker().syncPendingReadings();
    expect(backend.count('/prepare'), 1);
    expect(backend.count('/oracle/submit-data'), 0);
    expect(backend.verifiedAuthSignatures, isEmpty);
    expect(result.acceptedCount, 0);
    expect(result.failedCount, 0);
    expect(result.pendingCount, 0);
    expect(result.droppedStaleCount, 1);
    expect(await noticeCount(), 1);
  });

  test('slow earlier upload expires the rest without replaying it', () async {
    await seed(const Duration(minutes: 49), count: 3);
    backend.afterResponse = (path) {
      if (path == '/oracle/submit-data') {
        clock = clock.add(const Duration(minutes: 2));
      }
    };
    final result = await worker().syncPendingReadings();
    expect(backend.count('/prepare'), 1);
    expect(backend.count('/oracle/submit-data'), 1);
    expect(result.acceptedCount, 1);
    expect(result.failedCount, 0);
    expect(result.pendingCount, 0);
    expect(result.droppedStaleCount, 2);
    expect(await noticeCount(), 2);
    final rows = await db.getReadingHistory();
    expect(rows, hasLength(1));
    expect(rows.single.synced, isTrue);
  });

  test('retry delay cannot upload a newly expired reading', () async {
    await seed(const Duration(minutes: 49));
    backend.failSubmitStatus = 408;
    onRetry = () {
      clock = clock.add(const Duration(minutes: 2));
      backend.failSubmitStatus = null;
    };
    final result = await worker().syncPendingReadings();
    expect(backend.count('/prepare'), 1);
    expect(backend.count('/oracle/submit-data'), 1);
    expect(result.acceptedCount, 0);
    expect(result.pendingCount, 0);
    expect(result.droppedStaleCount, 1);
    expect(await noticeCount(), 1);
  });

  test('registration delay cannot prepare an expired reading', () async {
    await seed(const Duration(minutes: 49));
    SharedPreferences.setMockInitialValues({});
    backend.registered = false;
    backend.afterResponse = (path) {
      if (path == '/weather/stations/mobile') {
        clock = clock.add(const Duration(minutes: 2));
      }
    };
    final result = await worker(foreground: true).syncPendingReadings();
    expect(backend.registrations, 1);
    expect(walletSigner.sessionsOpened, 1);
    expect(backend.count('/prepare'), 0);
    expect(result.acceptedCount, 0);
    expect(result.pendingCount, 0);
    expect(result.droppedStaleCount, 1);
  });

  test('exact cutoff survives; older by one second is removed', () async {
    await seed(const Duration(minutes: 50, seconds: 1));
    await seed(const Duration(minutes: 50));
    final result = await worker().syncPendingReadings();
    expect(result.acceptedCount, 1);
    expect(result.droppedStaleCount, 1);
    expect(backend.count('/prepare'), 1);
    expect(backend.verifiedAuthSignatures, hasLength(1));
    expect(await noticeCount(), 1);
  });
}
