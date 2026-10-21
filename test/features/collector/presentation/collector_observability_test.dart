import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';

import '../../../test_helpers/fakes.dart';

class _TestAppPreferencesStore extends AppPreferencesStore {
  @override
  Future<AppPreferences> load() async => const AppPreferences();

  @override
  Future<void> save(AppPreferences preferences) async {}
}

class _FakeSyncWorker extends SyncWorker {
  _FakeSyncWorker(this._result);

  final SyncRunResult _result;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();

  @override
  Future<SyncRunResult> syncPendingReadings({bool includeIdempotencyKey = false}) async => _result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('collector sync failures emit structured diagnostics', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final sink = MemoryLogSink();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        collectorRepositoryProvider.overrideWithValue(
          FakeCollectorRepository(pendingCount: 2),
        ),
        syncWorkerProvider.overrideWithValue(
          _FakeSyncWorker(
            const SyncRunResult(
              acceptedCount: 0,
              failedCount: 1,
              pendingCount: 2,
              reason: SyncRunReason.offline,
              message: 'Offline. Waiting for connection.',
            ),
          ),
        ),
        collectorPreferencesProvider.overrideWithValue(
          const CollectorPreferences(),
        ),
        appPreferencesStoreProvider.overrideWithValue(
          _TestAppPreferencesStore(),
        ),
        appLoggerProvider.overrideWithValue(
          AppLogger(sinks: <LogSink>[sink], verbose: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(collectorProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await notifier.syncPendingData();

    final syncEntry = sink.entries.singleWhere(
      (entry) => entry.event == 'collector_sync_result',
    );
    expect(syncEntry.fields['reason'], 'offline');
    expect(syncEntry.fields['pendingCount'], 2);
    expect(syncEntry.fields['message'], 'Offline. Waiting for connection.');
  });

  test('a not-registered sync logs a station_not_registered event', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        collectorRepositoryProvider.overrideWithValue(
          FakeCollectorRepository(pendingCount: 2),
        ),
        syncWorkerProvider.overrideWithValue(
          _FakeSyncWorker(
            const SyncRunResult(
              acceptedCount: 0,
              failedCount: 2,
              pendingCount: 2,
              reason: SyncRunReason.stationNotRegistered,
              message: SyncWorker.stationNotRegisteredMessage,
            ),
          ),
        ),
        collectorPreferencesProvider.overrideWithValue(
          const CollectorPreferences(),
        ),
        appPreferencesStoreProvider.overrideWithValue(
          _TestAppPreferencesStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(collectorProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await notifier.syncPendingData();

    expect(
      container.read(collectorProvider).syncMessage,
      SyncWorker.stationNotRegisteredMessage,
    );
    final events = await container
        .read(collectorPreferencesProvider)
        .loadValidationEvents();
    expect(events.map((e) => e.code), contains('station_not_registered'));
  });
}
