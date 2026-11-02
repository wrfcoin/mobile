import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, visibleForTesting;
import 'package:workmanager/workmanager.dart';

import '../../features/collector/data/datasources/battery_monitor.dart';
import '../../features/collector/data/datasources/sensor_data_source.dart';
import '../../features/collector/data/repositories/collector_repository_impl.dart';
import '../../features/collector/data/services/collection_runner.dart';
import '../../features/collector/data/services/collector_preferences.dart';
import '../../features/collector/domain/collection_run.dart';
import '../../features/notifications/data/ntfy_poller.dart';
import '../../services/api/api_client.dart';
import '../../services/crypto/wallet_secure_storage.dart';
import '../../services/location/location_service.dart';
import '../../services/storage/db_path_stub.dart'
    if (dart.library.io) '../../services/storage/db_path.dart';
import '../../services/storage/local_db.dart';
import 'sync_worker.dart';

const sensorTaskName = 'com.wrfcoin.sensorCollection';
const syncTaskName = 'com.wrfcoin.dataSync';
const payoutPollTaskName = 'com.wrfcoin.payoutPoll';

CollectorRepository _createRepository(AppDatabase db) {
  return CollectorRepository(
    sensorDataSource: SensorDataSource(LocationService()),
    batteryMonitor: BatteryMonitor(),
    apiClient: ApiClient(),
    db: db,
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case sensorTaskName:
        await _collectSensorData();
        return true;
      case syncTaskName:
        await _syncPendingData();
        return true;
      case payoutPollTaskName:
        await pollPayoutNotificationsInBackground();
        return true;
      default:
        return false;
    }
  });
}

Future<void> _collectSensorData() async {
  final db = AppDatabase(openAppDatabase());
  try {
    final repository = _createRepository(db);
    final preferences = await const CollectorPreferences().load();
    await runCollectionJob(
      CollectionRunner(repository),
      batteryThreshold: preferences.batteryThreshold,
      baseIntervalMinutes: await repository.recommendedIntervalMinutes(
        preferences.intervalMinutes,
      ),
    );
  } finally {
    await db.close();
  }
}

/// One WorkManager collection run. A run that saved no reading throws, so
/// WorkManager records a failure, never a success.
@visibleForTesting
Future<void> runCollectionJob(
  CollectionRunner runner, {
  required int batteryThreshold,
  required int baseIntervalMinutes,
}) async {
  final result = await runner.collect(
    source: ReadingSource.job,
    batteryThreshold: batteryThreshold,
    baseIntervalMinutes: baseIntervalMinutes,
  );
  if (!result.isSuccess) {
    throw CollectionRunFailed(CollectionRunner.outcomeOf(result));
  }
}

Future<void> _syncPendingData() async {
  // The Workmanager isolate never starts a wallet login: the foreground
  // app owns the login guard (mobile#313).
  final worker = SyncWorker(
    walletSecureStorage: const WalletSecureStorage(),
    canStartLogin: false,
  );
  final db = AppDatabase(openAppDatabase());
  try {
    await runSyncJob(
      worker.syncPendingReadings,
      db,
      kind: CollectionRunKind.syncJob,
    );
  } finally {
    await db.close();
  }
}

/// One upload run: saves its result, and throws unless it did its job.
Future<SyncRunResult> runSyncJob(
  Future<SyncRunResult> Function() sync,
  CollectorLocalStore store, {
  required String kind,
  DateTime Function() now = DateTime.now,
}) async {
  final startedAt = now();
  final SyncRunResult result;
  try {
    result = await sync();
  } catch (error) {
    await store.recordCollectionRun(
      kind: kind,
      outcome: CollectionOutcome.error,
      detail: error.runtimeType.toString(),
      startedAt: startedAt,
      finishedAt: now(),
    );
    rethrow;
  }
  await store.recordCollectionRun(
    kind: kind,
    outcome: result.reason.name,
    acceptedCount: result.acceptedCount,
    startedAt: startedAt,
    finishedAt: now(),
  );
  if (!syncRunSucceeded(result.reason)) {
    throw CollectionRunFailed(result.reason.name);
  }
  return result;
}

/// Runs [action], swallowing the errors Workmanager throws on platforms
/// without an implementation (web already short-circuits, but desktop and
/// the flutter_test VM reach the placeholder implementation). Background
/// scheduling is best-effort — user-facing flows like consent revocation
/// must not crash because it is unavailable.
Future<void> _bestEffortBackgroundWork(
  String what,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on UnimplementedError {
    debugPrint('$what unavailable on this platform');
  } on UnsupportedError {
    debugPrint('$what unavailable on this platform');
  }
}

Future<void> initializeBackgroundWork() async {
  if (kIsWeb) return;
  await _bestEffortBackgroundWork(
    'Background work initialization',
    () => Workmanager().initialize(callbackDispatcher),
  );
}

Future<void> registerSensorWorker({
  Duration interval = const Duration(minutes: 15),
  ExistingPeriodicWorkPolicy policy = ExistingPeriodicWorkPolicy.replace,
}) async {
  if (kIsWeb) {
    debugPrint('Background sensor worker unavailable on web');
    return;
  }
  await _bestEffortBackgroundWork(
    'Background sensor worker',
    () => Workmanager().registerPeriodicTask(
      sensorTaskName,
      sensorTaskName,
      frequency: interval,
      // A replaced job runs at once. Only a change the user made does that.
      existingWorkPolicy: policy,
      constraints: Constraints(networkType: NetworkType.notRequired),
    ),
  );
}

Future<void> registerSyncWorker({
  ExistingPeriodicWorkPolicy policy = ExistingPeriodicWorkPolicy.replace,
}) async {
  if (kIsWeb) {
    debugPrint('Background sync worker unavailable on web');
    return;
  }
  await _bestEffortBackgroundWork(
    'Background sync worker',
    () => Workmanager().registerPeriodicTask(
      syncTaskName,
      syncTaskName,
      frequency: const Duration(minutes: 15),
      // A replaced job runs at once. Only a change the user made does that.
      existingWorkPolicy: policy,
      constraints: Constraints(networkType: NetworkType.connected),
    ),
  );
}

/// The periodic check of this phone's payout topic (15 minutes is Android's
/// floor). It survives collection being turned off: it is about being paid.
Future<void> registerPayoutPollWorker() async {
  if (kIsWeb) return;
  await _bestEffortBackgroundWork(
    'Payout notification check',
    () => Workmanager().registerPeriodicTask(
      payoutPollTaskName,
      payoutPollTaskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    ),
  );
}

Future<void> cancelPayoutPollWorker() async {
  if (kIsWeb) return;
  await _bestEffortBackgroundWork(
    'Payout notification cancellation',
    () => Workmanager().cancelByUniqueName(payoutPollTaskName),
  );
}

Future<void> cancelCollectionWorkers() async {
  if (kIsWeb) return;
  await _bestEffortBackgroundWork('Background work cancellation', () async {
    await Workmanager().cancelByUniqueName(sensorTaskName);
    await Workmanager().cancelByUniqueName(syncTaskName);
  });
}
