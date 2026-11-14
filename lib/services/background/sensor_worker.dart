import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/preferences/app_preferences.dart';

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
        await runIfCollectionAllowed(_collectSensorData);
        return true;
      case syncTaskName:
        await runIfCollectionAllowed(_syncPendingData);
        return true;
      case payoutPollTaskName:
        await pollPayoutNotificationsInBackground();
        return true;
      default:
        return false;
    }
  });
}

/// Whether the user still wants collection: both consents and the Collect
/// switch, read fresh. This engine can outlive the app session that wrote
/// them, so its copy of the preferences may be stale.
Future<bool> collectionStillAllowed() async {
  await (await SharedPreferences.getInstance()).reload();
  final consent = (await const AppPreferencesStore().load()).consent;
  if (!consent.canCollect) return false;
  return (await const CollectorPreferences().load()).isCollecting;
}

/// Runs a collection or upload job only while the user still wants
/// collection. A job left behind after consent was withdrawn (the app was
/// killed between saving the choice and cancelling the jobs) cancels itself
/// and reads or sends nothing.
@visibleForTesting
Future<void> runIfCollectionAllowed(
  Future<void> Function() job, {
  Future<bool> Function() allowed = collectionStillAllowed,
  Future<void> Function() cancel = cancelCollectionWorkers,
}) async {
  if (!await allowed()) {
    await cancel();
    return;
  }
  await job();
}

Future<void> _collectSensorData() async {
  final db = AppDatabase(openAppDatabase());
  try {
    final repository = _createRepository(db);
    final preferences = await const CollectorPreferences().load();
    await runSensorJob(repository, preferences);
  } finally {
    await db.close();
  }
}

/// The WorkManager reading. It passes the user's own interval: the reading
/// applies the low-battery backoff itself, so passing the backed-off one
/// doubled it twice (a reading every hour instead of every 30 minutes).
@visibleForTesting
Future<void> runSensorJob(
  CollectorRepository repository,
  CollectorPreferencesState preferences,
) => runCollectionJob(
  CollectionRunner(repository),
  batteryThreshold: preferences.batteryThreshold,
  baseIntervalMinutes: preferences.intervalMinutes,
);

/// How far past due a reading must be before the job takes it. The service and
/// the job fire on the same 15 minutes; left equal they race, and one tick can
/// save two readings. The service reads a fresh location and the job only reuses
/// one, so the service goes first and the job covers for it when it has stopped.
/// With the service stopped, the job collects on every second run.
const serviceBackstopGrace = Duration(minutes: 5);

/// One WorkManager collection run. A run that saved no reading for a real
/// reason (no location, no barometer, low battery, an error) throws, so
/// WorkManager records a failure. A run that was simply not due yet (the
/// service or an app open took the reading) is a success: with the service
/// running that is the job's usual answer, and a failure every cycle only
/// hid the real ones. The run row still says `not_due`.
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
    dueGrace: serviceBackstopGrace,
  );
  if (!result.isSuccess &&
      result.failureReason != CollectReadingFailureReason.stationaryBackoff) {
    throw CollectionRunFailed(CollectionRunner.outcomeOf(result));
  }
}

Future<void> _syncPendingData() async {
  // The Workmanager isolate never starts a wallet login: the foreground
  // app owns the login guard (mobile#313).
  final worker = SyncWorker(
    walletSecureStorage: const WalletSecureStorage(),
    canStartLogin: false,
    // Asked again before each batch: consent can go off mid-run.
    collectionAllowed: collectionStillAllowed,
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
      detail: describeRunError(error),
      startedAt: startedAt,
      finishedAt: now(),
    );
    rethrow;
  }
  final succeeded = syncRunSucceeded(result.reason);
  await store.recordCollectionRun(
    kind: kind,
    outcome: result.reason.name,
    // A run that left readings behind says why, in the words the app shows.
    detail: succeeded ? null : runDetail(result.message),
    acceptedCount: result.acceptedCount,
    startedAt: startedAt,
    finishedAt: now(),
  );
  if (!succeeded) {
    throw CollectionRunFailed(result.reason.name);
  }
  return result;
}

/// The longest detail a run row keeps.
const maxRunDetailLength = 240;

/// [message] trimmed to one short line for a run row, or null when empty.
String? runDetail(String? message) {
  final text = message?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text == null || text.isEmpty) return null;
  return text.length <= maxRunDetailLength
      ? text
      : '${text.substring(0, maxRunDetailLength - 1)}…';
}

/// What a crashed run saves: the error's type, and for a network error its
/// kind and HTTP status (a TLS refusal reads `DioException.badCertificate`
/// or `.connectionError`). Never the message, which may quote a server body.
String describeRunError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    return 'DioException.${error.type.name}'
        '${status == null ? '' : ' HTTP $status'}';
  }
  return error.runtimeType.toString();
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
