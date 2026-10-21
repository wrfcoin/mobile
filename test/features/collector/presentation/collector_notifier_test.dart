import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';

import '../../../test_helpers/fakes.dart';

void main() {
  group('CollectorNotifier.syncPendingData', () {
    late _FakeSyncWorker syncWorker;
    late ProviderContainer container;
    late CollectorNotifier notifier;
    late _CollectorRepo repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      syncWorker = _FakeSyncWorker(
        const SyncRunResult(
          acceptedCount: 0,
          failedCount: 0,
          pendingCount: 0,
          reason: SyncRunReason.idle,
        ),
      );
      repository = _CollectorRepo();
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          collectorRepositoryProvider.overrideWithValue(repository),
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
        ],
      );
      notifier = container.read(collectorProvider.notifier);
      // Let _restoreState settle
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() {
      container.dispose();
    });

    test('missing location explicitly asks permission to register', () async {
      repository.locationUnavailable = true;
      await notifier.collectNow();
      expect(
        notifier.state.syncMessage,
        contains('Allow location to register'),
      );
      expect(syncWorker.calls, 0);
    });

    test('syncPendingData accumulates reward totals in state', () async {
      syncWorker.nextResult = const SyncRunResult(
        acceptedCount: 3,
        failedCount: 0,
        pendingCount: 0,
        reason: SyncRunReason.success,
        rewardWrfTotal: 1.5,
        rewardTotalsAvailable: true,
      );

      await notifier.syncPendingData();

      expect(notifier.state.syncedSubmissionCount, 3);
      expect(notifier.state.earnedRewardWrf, closeTo(1.5, 0.0001));
      expect(notifier.state.rewardTotalsAvailable, isTrue);

      // Sync again — totals accumulate
      await notifier.syncPendingData();

      expect(notifier.state.syncedSubmissionCount, 6);
      expect(notifier.state.earnedRewardWrf, closeTo(3.0, 0.0001));
    });

    test('syncPendingData records submission metadata in state', () async {
      syncWorker.nextResult = const SyncRunResult(
        acceptedCount: 1,
        failedCount: 0,
        pendingCount: 0,
        reason: SyncRunReason.success,
        lastSubmissionId: 'sub-99',
        lastSubmissionStatus: 'confirmed',
      );

      await notifier.syncPendingData();

      expect(notifier.state.lastSubmissionId, 'sub-99');
      expect(notifier.state.lastSubmissionStatus, 'confirmed');
    });

    // Design §200: a cancelled biometric prompt is not retried by itself. The
    // reconnect triggers stand down until an explicit foreground sync or Collect Now.
    group('after a cancelled biometric prompt', () {
      const refused = SyncRunResult(
        acceptedCount: 0,
        failedCount: 0,
        pendingCount: 3,
        reason: SyncRunReason.signingRefused,
      );
      const ok = SyncRunResult(
        acceptedCount: 3,
        failedCount: 0,
        pendingCount: 0,
        reason: SyncRunReason.success,
      );

      test('automatic syncs do not prompt again', () async {
        syncWorker.nextResult = refused;
        await notifier.autoSyncPendingData();
        expect(syncWorker.calls, 1);

        await notifier.autoSyncPendingData();
        await notifier.autoSyncPendingData();

        expect(syncWorker.calls, 1);
      });

      test(
        'Collect Now is a user action that re-arms a refused prompt',
        () async {
          syncWorker.nextResult = refused;
          await notifier.autoSyncPendingData();
          syncWorker.nextResult = ok;
          await notifier.collectNow();
          expect(syncWorker.calls, 2);
        },
      );

      test('an explicit sync prompts again and resumes automatic syncs', () async {
        syncWorker.nextResult = refused;
        await notifier.autoSyncPendingData();
        expect(syncWorker.calls, 1);

        syncWorker.nextResult = ok;
        await notifier.syncPendingData();
        expect(syncWorker.calls, 2);

        await notifier.autoSyncPendingData();
        expect(syncWorker.calls, 3);
      });

      test('an explicit sync that is refused again keeps automatic syncs off', () async {
        syncWorker.nextResult = refused;
        await notifier.syncPendingData();
        await notifier.autoSyncPendingData();

        expect(syncWorker.calls, 1);
      });

      test('other outcomes never pause automatic syncs', () async {
        syncWorker.nextResult = const SyncRunResult(
          acceptedCount: 0,
          failedCount: 3,
          pendingCount: 3,
          reason: SyncRunReason.failure,
        );
        await notifier.autoSyncPendingData();
        await notifier.autoSyncPendingData();

        expect(syncWorker.calls, 2);
      });
    });
  });
}

class _FakeSyncWorker extends SyncWorker {
  SyncRunResult nextResult;
  int calls = 0;

  _FakeSyncWorker(this.nextResult);

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();

  @override
  Future<SyncRunResult> syncPendingReadings({bool includeIdempotencyKey = false}) async {
    calls++;
    return nextResult;
  }
}

class _TestAppPreferencesStore extends AppPreferencesStore {
  _TestAppPreferencesStore();

  @override
  Future<AppPreferences> load() async => const AppPreferences(
    consent: ConsentSettings(sensorCollection: true, preciseLocation: true),
  );

  @override
  Future<void> save(AppPreferences preferences) async {}
}

class _CollectorRepo extends FakeCollectorRepository {
  _CollectorRepo()
    : super(
        reading: SensorReadingModel(
          latitude: 1,
          longitude: 2,
          pressureHpa: 1000,
          timestamp: DateTime.utc(2026, 9, 29),
        ),
      );
  bool locationUnavailable = false;
  @override
  Future<CollectReadingResult> collectReading({
    int batteryThreshold = 15,
    int baseIntervalMinutes = 15,
    bool force = false,
  }) async => locationUnavailable
      ? const CollectReadingResult.failure(
          CollectReadingFailureReason.locationUnavailable,
        )
      : super.collectReading(
          batteryThreshold: batteryThreshold,
          baseIntervalMinutes: baseIntervalMinutes,
          force: force,
        );
}
