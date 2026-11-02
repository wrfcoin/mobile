import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:workmanager/workmanager.dart';

import '../../features/collector/data/datasources/battery_monitor.dart';
import '../../features/collector/data/datasources/sensor_data_source.dart';
import '../../features/collector/data/repositories/collector_repository_impl.dart';
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
    final intervalMinutes = await repository.recommendedIntervalMinutes(15);
    await repository.collectReading(baseIntervalMinutes: intervalMinutes);
  } finally {
    await db.close();
  }
}

Future<void> _syncPendingData() async {
  // The Workmanager isolate never starts a wallet login: the foreground
  // app owns the login guard (mobile#313).
  await SyncWorker(
    walletSecureStorage: const WalletSecureStorage(),
    canStartLogin: false,
  ).syncPendingReadings();
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
      // Lane 1: replace any existing registration so interval changes take
      // effect immediately without needing to cancel first.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.notRequired),
    ),
  );
}

Future<void> registerSyncWorker() async {
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
      // Lane 1: replace any existing registration so re-enabling collection
      // always resets the sync schedule cleanly.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
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
