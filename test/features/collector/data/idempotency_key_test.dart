import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_helpers/fake_station_backend.dart';

import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fakes.dart';

/// Notifier that returns a preset [FeatureFlags] state without touching
/// SharedPreferences.  Used to override [featureFlagsProvider] in tests so the
/// CollectorNotifier sees a specific `enableConnectivityHardening` value.
class _FakeFeatureFlagsNotifier extends FeatureFlagsNotifier {
  _FakeFeatureFlagsNotifier(this._initial);
  final FeatureFlags _initial;
  @override
  FeatureFlags build() => _initial;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Intercepts every POST request, records the body, and returns an accepted
/// response so CollectorRepository.submitBatch treats the reading as synced.
class _CaptureInterceptor extends Interceptor {
  final List<Map<String, dynamic>> capturedBodies = <Map<String, dynamic>>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final prepared = answerPrepare(options);
    if (prepared != null) {
      // Only the signed submit leg is captured.
      handler.resolve(prepared);
      return;
    }
    if (options.data is Map<String, dynamic>) {
      capturedBodies.add(
        Map<String, dynamic>.from(options.data as Map<String, dynamic>),
      );
    }
    // Resolve immediately with a success payload — no real network hit.
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'success': true, 'submissionId': 'sub-test-1'},
      ),
    );
  }
}

/// Builds a minimal [SensorReading] row usable by [CollectorRepository.submitBatch].
SensorReading _reading({
  int id = 1,
  double lat = 47.6,
  double lng = -122.3,
  double pressure = 1013.25,
  DateTime? ts,
}) {
  return SensorReading(
    id: id,
    latitude: lat,
    longitude: lng,
    pressureHpa: pressure,
    timestamp: ts ?? DateTime.utc(2026, 4, 17, 12, 0, 0),
    synced: false,
  );
}

/// Builds a [CollectorRepository] whose Dio is wired through [interceptor].
CollectorRepository _repoWithInterceptor(_CaptureInterceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
  dio.interceptors.add(interceptor);
  return CollectorRepository(
    sensorDataSource: FakeCollectorRepository().sensorDataSource,
    batteryMonitor: FakeBatteryMonitor(),
    apiClient: ApiClient(dio: dio, allowUnauthenticatedRequests: true),
    db: FakeCollectorLocalStore(),
  );
}

// ---------------------------------------------------------------------------
// SyncWorker stub that records the includeIdempotencyKey flag value
// ---------------------------------------------------------------------------

class _CapturingSyncWorker extends SyncWorker {
  final List<bool> capturedFlags = <bool>[];

  _CapturingSyncWorker();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();

  @override
  Future<SyncRunResult> syncPendingReadings({
    bool includeIdempotencyKey = false,
  }) async {
    capturedFlags.add(includeIdempotencyKey);
    return const SyncRunResult(
      acceptedCount: 0,
      failedCount: 0,
      pendingCount: 0,
      reason: SyncRunReason.idle,
    );
  }
}

class _TestAppPreferencesStore extends AppPreferencesStore {
  @override
  Future<AppPreferences> load() async => const AppPreferences();

  @override
  Future<void> save(AppPreferences preferences) async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late CollectKey session;
  setUpAll(() async {
    session = await syntheticCollectKey();
  });

  group('FeatureFlags.enableConnectivityHardening', () {
    test('defaults to false', () {
      const flags = FeatureFlags();
      expect(flags.enableConnectivityHardening, isFalse);
    });

    test('copyWith enables without affecting other flags', () {
      const flags = FeatureFlags(enableOfflineBuffer: true);
      final updated = flags.copyWith(enableConnectivityHardening: true);
      expect(updated.enableConnectivityHardening, isTrue);
      expect(updated.enableOfflineBuffer, isTrue);
      expect(updated.enableLocalCommunities, isFalse);
    });

    test('SharedPreferences round-trip persists and loads the flag', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      final container1 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container1.dispose);

      expect(
        container1.read(featureFlagsProvider).enableConnectivityHardening,
        isFalse,
      );
      await container1
          .read(featureFlagsProvider.notifier)
          .setConnectivityHardening(enabled: true);
      expect(
        container1.read(featureFlagsProvider).enableConnectivityHardening,
        isTrue,
      );

      // A fresh container reading the same SharedPreferences instance sees
      // the persisted value.
      final container2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container2.dispose);
      expect(
        container2.read(featureFlagsProvider).enableConnectivityHardening,
        isTrue,
      );
    });
  });

  group('CollectorRepository.submitBatch — idempotency key', () {
    test('no idempotencyKey in body when flag is false', () async {
      final interceptor = _CaptureInterceptor();
      final repo = _repoWithInterceptor(interceptor);

      await repo.submitBatch(
        [_reading()],
        walletAddress: 'wrf1testaddr',
        signer: session,
        includeIdempotencyKey: false,
      );

      expect(interceptor.capturedBodies, hasLength(1));
      expect(
        interceptor.capturedBodies.first.containsKey('idempotencyKey'),
        isFalse,
      );
    });

    test('idempotencyKey present in body when flag is true', () async {
      final interceptor = _CaptureInterceptor();
      final repo = _repoWithInterceptor(interceptor);

      await repo.submitBatch(
        [_reading()],
        walletAddress: 'wrf1testaddr',
        signer: session,
        includeIdempotencyKey: true,
      );

      expect(interceptor.capturedBodies, hasLength(1));
      expect(
        interceptor.capturedBodies.first.containsKey('idempotencyKey'),
        isTrue,
      );
    });

    test(
      'idempotencyKey has correct format: deviceId:readingId:epochMs',
      () async {
        final interceptor = _CaptureInterceptor();
        final repo = _repoWithInterceptor(interceptor);
        final ts = DateTime.utc(2026, 4, 17, 12, 0, 0);
        const walletAddress = 'wrf1testaddr';

        await repo.submitBatch(
          [_reading(id: 7, ts: ts)],
          walletAddress: walletAddress,
          signer: session,
          includeIdempotencyKey: true,
        );

        final body = interceptor.capturedBodies.first;
        final key = body['idempotencyKey'] as String;
        final deviceId = 'mobile:$walletAddress';
        expect(key, 'mobile:$walletAddress:7:${ts.millisecondsSinceEpoch}');
        expect(key, startsWith('$deviceId:'));
      },
    );

    test(
      'same reading produces identical key on two calls (determinism)',
      () async {
        final ts = DateTime.utc(2026, 4, 17, 9, 30, 0);
        final r = _reading(id: 42, ts: ts);
        const walletAddress = 'wrf1stable';

        final interceptor1 = _CaptureInterceptor();
        final repo1 = _repoWithInterceptor(interceptor1);
        await repo1.submitBatch(
          [r],
          walletAddress: walletAddress,
          signer: session,
          includeIdempotencyKey: true,
        );

        final interceptor2 = _CaptureInterceptor();
        final repo2 = _repoWithInterceptor(interceptor2);
        await repo2.submitBatch(
          [r],
          walletAddress: walletAddress,
          signer: session,
          includeIdempotencyKey: true,
        );

        final key1 =
            interceptor1.capturedBodies.first['idempotencyKey'] as String;
        final key2 =
            interceptor2.capturedBodies.first['idempotencyKey'] as String;
        expect(key1, equals(key2));
      },
    );

    test('different readings produce different keys', () async {
      final interceptor = _CaptureInterceptor();
      final repo = _repoWithInterceptor(interceptor);

      await repo.submitBatch(
        [_reading(id: 1), _reading(id: 2)],
        walletAddress: 'wrf1testaddr',
        signer: session,
        includeIdempotencyKey: true,
      );

      expect(interceptor.capturedBodies, hasLength(2));
      final key1 = interceptor.capturedBodies[0]['idempotencyKey'] as String;
      final key2 = interceptor.capturedBodies[1]['idempotencyKey'] as String;
      expect(key1, isNot(equals(key2)));
    });
  });

  group('CollectorRepository.submitBatch — pressure payload shape (#217)', () {
    test('dataType is pressure_hpa and value is a scalar number', () async {
      final interceptor = _CaptureInterceptor();
      final repo = _repoWithInterceptor(interceptor);

      await repo.submitBatch(
        [_reading(id: 3, pressure: 1007.5)],
        walletAddress: 'wrf1testaddr',
        signer: session,
      );

      expect(interceptor.capturedBodies, hasLength(1));
      final body = interceptor.capturedBodies.first;
      // Backend applyDataTypeValue() only maps 'pressure' / 'pressure_hpa'.
      expect(body['dataType'], 'pressure_hpa');
      // value must be a scalar number, not an object — an object coerces to
      // NaN → 0 in the backend canonical reading (#217).
      expect(body['value'], isA<num>());
      expect(body['value'], 1007.5);
    });

    test('deviceId/readingId move to metadata; no walletAddress in value', () async {
      final interceptor = _CaptureInterceptor();
      final repo = _repoWithInterceptor(interceptor);

      await repo.submitBatch(
        [_reading(id: 9)],
        walletAddress: 'wrf1testaddr',
        signer: session,
      );

      final body = interceptor.capturedBodies.first;
      // value is scalar, so it exposes no walletAddress the backend must derive
      // from the JWT instead.
      expect(body['value'], isNot(isA<Map>()));
      final metadata = body['metadata'] as Map<String, dynamic>;
      expect(metadata['deviceId'], 'mobile:wrf1testaddr');
      expect(metadata['readingId'], 9);
    });
  });

  group('CollectorNotifier — flag threading to SyncWorker', () {
    late _CapturingSyncWorker syncWorker;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      syncWorker = _CapturingSyncWorker();
    });

    ProviderContainer makeContainer({
      required bool enableConnectivityHardening,
    }) {
      final container = ProviderContainer(
        overrides: [
          collectorRepositoryProvider.overrideWithValue(
            FakeCollectorRepository(),
          ),
          syncWorkerProvider.overrideWithValue(syncWorker),
          collectorPreferencesProvider.overrideWithValue(
            const CollectorPreferences(),
          ),
          appPreferencesStoreProvider.overrideWithValue(
            _TestAppPreferencesStore(),
          ),
          appLoggerProvider.overrideWithValue(
            const AppLogger(sinks: <LogSink>[], verbose: false),
          ),
          featureFlagsProvider.overrideWith(
            () => _FakeFeatureFlagsNotifier(
              FeatureFlags(
                enableConnectivityHardening: enableConnectivityHardening,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('passes false to syncPendingReadings when flag is disabled', () async {
      final container = makeContainer(enableConnectivityHardening: false);
      final notifier = container.read(collectorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      await notifier.syncPendingData();

      expect(syncWorker.capturedFlags, hasLength(1));
      expect(syncWorker.capturedFlags.first, isFalse);
    });

    test('passes true to syncPendingReadings when flag is enabled', () async {
      final container = makeContainer(enableConnectivityHardening: true);
      final notifier = container.read(collectorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      await notifier.syncPendingData();

      expect(syncWorker.capturedFlags, hasLength(1));
      expect(syncWorker.capturedFlags.first, isTrue);
    });

    test('flag stays false across multiple syncs when disabled', () async {
      final container = makeContainer(enableConnectivityHardening: false);
      final notifier = container.read(collectorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      await notifier.syncPendingData();
      await notifier.syncPendingData();

      expect(syncWorker.capturedFlags, everyElement(isFalse));
    });
  });
}
