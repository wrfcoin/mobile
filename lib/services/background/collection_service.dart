import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/preferences/app_preferences.dart';
import '../../features/collector/data/datasources/battery_monitor.dart';
import '../../features/collector/data/datasources/sensor_data_source.dart';
import '../../features/collector/data/repositories/collector_repository_impl.dart';
import '../../features/collector/data/services/collection_runner.dart';
import '../../features/collector/data/services/collector_preferences.dart';
import '../../features/collector/domain/collection_run.dart';
import '../api/api_client.dart';
import '../crypto/wallet_secure_storage.dart';
import '../location/location_service.dart';
import '../storage/db_path_stub.dart'
    if (dart.library.io) '../storage/db_path.dart';
import '../storage/local_db.dart';
import 'sensor_worker.dart';
import 'sync_worker.dart';

// The foreground service that collects with the app closed. Android gives a
// closed app no sensor events and no location unless a foreground service is
// running, and a location service may only be started while the app is on
// screen (or, on some versions, not restarted at all from the background).
// So the Collect toggle starts it, and opening the app starts it again if
// Android stopped it. It does not start itself after a reboot.

const _stopButtonId = 'stop_collecting';
const _serviceId = 888;

/// Sent to the app, when it is open, after the notification's Stop button.
const collectionStoppedMessage = 'collection_stopped';

<<<<<<< HEAD
/// Sent to the app, when it is open, after each run.
const collectionTickMessage = 'collection_tick';

const _notificationTitle = 'WRFCoin is collecting weather data';
=======
/// Says plainly what is running, and that it uses rough location.
const collectionNotificationTitle = 'Collecting weather with your rough location';
>>>>>>> feat/collect-battery-ask

enum CollectionServiceStart {
  started,

  /// There is no foreground service on this platform.
  unsupported,

  /// Android refused, or the plugin failed.
  failed,
}

final collectionServiceProvider = Provider<CollectionServiceController>(
  (ref) => const CollectionServiceController(),
);

class CollectionServiceController {
  const CollectionServiceController();

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> get isRunning async {
    if (!_supported) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// The system's notification permission dialog (Android 13+). The service
  /// runs either way, but without this its Stop button is hidden.
  Future<void> requestNotificationPermission() async {
    if (!_supported) return;
    try {
      final current = await FlutterForegroundTask.checkNotificationPermission();
      if (current != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Whether Android's battery limits apply to this app. Null when unknown.
  Future<bool?> get isBatteryLimited async {
    if (!_supported) return null;
    try {
      return !await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// The system's own "let this app ignore battery limits" dialog.
  Future<void> requestBatteryExemption() async {
    if (!_supported) return;
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Starts the service, or does nothing if it is running. Call only while
  /// the app is on screen and location is granted.
  Future<CollectionServiceStart> start({required int intervalMinutes}) async {
    if (!_supported) return CollectionServiceStart.unsupported;
    try {
      _init(intervalMinutes);
      if (await FlutterForegroundTask.isRunningService) {
        return CollectionServiceStart.started;
      }
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationTitle: collectionNotificationTitle,
        notificationText: 'Starting',
        notificationButtons: const [
          NotificationButton(id: _stopButtonId, text: 'Stop'),
        ],
        callback: collectionServiceEntry,
      );
      return result is ServiceRequestSuccess
          ? CollectionServiceStart.started
          : CollectionServiceStart.failed;
    } on MissingPluginException {
      return CollectionServiceStart.failed;
    } on PlatformException {
      return CollectionServiceStart.failed;
    }
  }

  Future<void> stop() async {
    if (!_supported) return;
    try {
      await FlutterForegroundTask.stopService();
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Applies a changed interval to a running service.
  Future<void> setInterval(int intervalMinutes) async {
    if (!_supported || !await isRunning) return;
    try {
      await FlutterForegroundTask.updateService(
        foregroundTaskOptions: _options(intervalMinutes),
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Whether this platform has the service at all.
  bool get supported => _supported;

  /// Calls [onStopped] when the notification's Stop button is used while the
  /// app is open, and [onTick] after each run. Returns a function that
  /// removes the listener.
  void Function() listen(void Function() onStopped, {void Function()? onTick}) {
    if (!_supported) return () {};
    void callback(Object data) {
      if (data == collectionStoppedMessage) onStopped();
      if (data == collectionTickMessage) onTick?.call();
    }

    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.addTaskDataCallback(callback);
    } on MissingPluginException {
      return () {};
    } on PlatformException {
      return () {};
    }
    return () => FlutterForegroundTask.removeTaskDataCallback(callback);
  }

  static ForegroundTaskOptions _options(int intervalMinutes) =>
      ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          Duration(minutes: intervalMinutes).inMilliseconds,
        ),
        // Android's boot broadcast cannot start a location service.
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        // The timer does not run while the CPU sleeps, so without this the
        // readings stop when the screen is off. It is the battery cost.
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: true,
      );

  static void _init(int intervalMinutes) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'wrfcoin_collection',
        channelName: 'Weather collection',
        channelDescription:
            'Shown while WRFCoin collects weather readings using your rough '
            'location.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: _options(intervalMinutes),
    );
  }
}

/// What one service tick did, in words short enough for a notification.
String collectionNotificationText(
  CollectReadingResult result,
  DateTime at, {
  required SyncRunReason? upload,
}) {
  final time = DateFormat.jm().format(at);
  if (result.isSuccess) {
    final uploaded = upload == SyncRunReason.success;
    return uploaded
        ? 'Last reading $time, uploaded'
        : 'Last reading $time, waiting to upload';
  }
  return switch (result.failureReason) {
    CollectReadingFailureReason.batteryLow =>
      'Paused at $time: battery is low',
    CollectReadingFailureReason.barometerUnavailable =>
      'No reading at $time: the barometer gave no data',
    CollectReadingFailureReason.locationUnavailable =>
      'No reading at $time: no location yet, open the app',
    CollectReadingFailureReason.locationTooOld =>
      'No reading at $time: location is over a day old, open the app',
    CollectReadingFailureReason.stationaryBackoff ||
    null => 'Running. Checked at $time',
  };
}

/// One tick of the service: stop if collection was turned off, otherwise take
/// a reading and upload what is queued. Returns the notification text, or
/// null if the service should stop.
@visibleForTesting
Future<String?> runCollectionTick({
  required Future<bool> Function() stillWanted,
  required Future<CollectReadingResult> Function() collect,
  required Future<SyncRunResult> Function() sync,
  DateTime Function() now = DateTime.now,
}) async {
  if (!await stillWanted()) return null;
  final result = await collect();
  SyncRunReason? upload;
  try {
    upload = (await sync()).reason;
  } on CollectionRunFailed catch (failed) {
    debugPrint('Collection service upload: ${failed.outcome}');
  }
  return collectionNotificationText(result, now(), upload: upload);
}

/// Saves "stopped", from the service isolate, so the app sees it when opened.
Future<void> _saveStopped() async {
  final preferences = await _freshPreferences();
  await const CollectorPreferences().save(
    preferences.copyWith(isCollecting: false),
  );
}

Future<CollectorPreferencesState> _freshPreferences() async {
  // This isolate outlives many app sessions: its copy can be stale.
  await (await SharedPreferences.getInstance()).reload();
  return const CollectorPreferences().load();
}

class _CollectionTaskHandler extends TaskHandler {
  bool _ticking = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _tick();

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_tick());

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == _stopButtonId) unawaited(_stop());
  }

  Future<void> _stop() async {
    await _saveStopped();
    await initializeBackgroundWork();
    await cancelCollectionWorkers();
    FlutterForegroundTask.sendDataToMain(collectionStoppedMessage);
    await FlutterForegroundTask.stopService();
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    final db = AppDatabase(openAppDatabase());
    try {
      final preferences = await _freshPreferences();
      final repository = CollectorRepository(
        sensorDataSource: SensorDataSource(LocationService()),
        batteryMonitor: BatteryMonitor(),
        apiClient: ApiClient(),
        db: db,
      );
      final worker = SyncWorker(
        walletSecureStorage: const WalletSecureStorage(),
        canStartLogin: false,
      );
      final text = await runCollectionTick(
        stillWanted: () async {
          final consent = (await const AppPreferencesStore().load()).consent;
          return preferences.isCollecting && consent.canCollect;
        },
        collect: () => CollectionRunner(repository).collect(
          source: ReadingSource.service,
          batteryThreshold: preferences.batteryThreshold,
          baseIntervalMinutes: preferences.intervalMinutes,
        ),
        sync: () => runSyncJob(
          worker.syncPendingReadings,
          db,
          kind: CollectionRunKind.syncService,
        ),
      );
      if (text == null) {
        await FlutterForegroundTask.stopService();
      } else {
        await FlutterForegroundTask.updateService(notificationText: text);
        FlutterForegroundTask.sendDataToMain(collectionTickMessage);
      }
    } catch (error) {
      // Stay alive for the next tick. CollectionRunner saved the reason.
      debugPrint('Collection service tick failed: ${error.runtimeType}');
    } finally {
      await db.close();
      _ticking = false;
    }
  }
}

@pragma('vm:entry-point')
void collectionServiceEntry() {
  FlutterForegroundTask.setTaskHandler(_CollectionTaskHandler());
}
