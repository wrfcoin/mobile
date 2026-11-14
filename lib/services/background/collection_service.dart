import 'dart:async';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        kIsWeb,
        visibleForTesting;
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
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
import 'collection_stopped_notice.dart';
import 'collection_wake.dart';
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

/// Sent to the app, when it is open, after each run.
const collectionTickMessage = 'collection_tick';

/// Says plainly what is running, and that it uses rough location.
const collectionNotificationTitle =
    'Collecting weather with your rough location';

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
      if (await FlutterForegroundTask.isRunningService) {
        _init(intervalMinutes, pluginWakeLock: await pluginWakeLockFallback());
        await clearCollectionStoppedNotice();
        return CollectionServiceStart.started;
      }
      // A fresh start tries the service's own lock again.
      await setPluginWakeLockFallback(false);
      _init(intervalMinutes, pluginWakeLock: false);
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
      if (result is! ServiceRequestSuccess) {
        return CollectionServiceStart.failed;
      }
      // Running again: the "collection stopped" notice no longer applies.
      await clearCollectionStoppedNotice();
      return CollectionServiceStart.started;
    } on MissingPluginException {
      return CollectionServiceStart.failed;
    } on PlatformException {
      return CollectionServiceStart.failed;
    }
  }

  Future<void> stop() async {
    if (!_supported) return;
    try {
      await clearCollectionStoppedNotice();
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
        foregroundTaskOptions: collectionTaskOptions(
          intervalMinutes,
          pluginWakeLock: await pluginWakeLockFallback(),
        ),
      );
      // The service's wake-up alarm is set from its own isolate.
      FlutterForegroundTask.sendDataToTask(collectionIntervalChangedMessage);
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

  static void _init(int intervalMinutes, {required bool pluginWakeLock}) {
    FlutterForegroundTask.init(
      androidNotificationOptions: collectionNotificationOptions(),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: collectionTaskOptions(
        intervalMinutes,
        pluginWakeLock: pluginWakeLock,
      ),
    );
  }
}

/// How the service runs. Its repeat timer does not count while the CPU
/// sleeps, and the plugin's answer to that is a wake lock held for as long as
/// the service runs, which kept the phone from ever sleeping. So the plugin's
/// lock is off: the service takes its own, one tick at a time, and an alarm
/// wakes it for the next (collection_wake.dart).
@visibleForTesting
ForegroundTaskOptions collectionTaskOptions(
  int intervalMinutes, {
  bool pluginWakeLock = false,
}) => ForegroundTaskOptions(
  eventAction: ForegroundTaskEventAction.repeat(
    Duration(minutes: intervalMinutes).inMilliseconds,
  ),
  // Android's boot broadcast cannot start a location service.
  autoRunOnBoot: false,
  autoRunOnMyPackageReplaced: false,
  // Only as the fallback when the service's own lock cannot be reached.
  allowWakeLock: pluginWakeLock,
  allowWifiLock: false,
  allowAutoRestart: true,
);

/// The status notice of the collection service. Android requires it while the
/// service runs. It must never sound or vibrate: it is rewritten after every
/// run (about every 15 minutes), so the channel is low importance with no sound
/// or vibration, and only the first post may alert at all.
@visibleForTesting
AndroidNotificationOptions collectionNotificationOptions() =>
    AndroidNotificationOptions(
      channelId: 'wrfcoin_collection',
      channelName: 'Weather collection',
      channelDescription:
          'Shown while WRFCoin collects weather readings using your rough '
          'location.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      playSound: false,
      enableVibration: false,
      onlyAlertOnce: true,
    );

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
    CollectReadingFailureReason.batteryLow => 'Paused at $time: battery is low',
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

/// The longest one service tick may take. A tick that hangs (a request that
/// never answers, a plugin call that never returns) would otherwise hold the
/// tick guard forever, and every later tick would return at once: the service
/// stays up, its notification stays, and nothing is collected or uploaded.
const collectionTickTimeout = Duration(minutes: 10);

/// The longest the tick's wake lock is held if nothing gives it back: the
/// tick's own limit, plus time to save why it failed.
const collectionWakeHold = Duration(minutes: 11);

/// Which step of a tick was running when it failed or ran out of time.
enum CollectionTickStage { settings, collect, upload }

/// One tick of the service: stop if collection was turned off, otherwise take
/// a reading and upload what is queued. Returns the notification text, or
/// null if the service should stop.
///
/// A tick that crashes outside collect and upload (which save their own run
/// rows), or runs past [timeout], is saved through [recordFailure] with the
/// step it was on, so the validation log says why, then rethrown.
@visibleForTesting
Future<String?> runCollectionTick({
  required Future<bool> Function() stillWanted,
  required Future<CollectReadingResult> Function() collect,
  required Future<SyncRunResult> Function() sync,
  DateTime Function() now = DateTime.now,
  Future<void> Function(String outcome, String detail)? recordFailure,
  Duration timeout = collectionTickTimeout,
}) async {
  var stage = CollectionTickStage.settings;
  Future<String?> tick() async {
    if (!await stillWanted()) return null;
    stage = CollectionTickStage.collect;
    final result = await collect();
    stage = CollectionTickStage.upload;
    SyncRunReason? upload;
    String uploadOutcome;
    try {
      upload = (await sync()).reason;
      uploadOutcome = upload.name;
    } on CollectionRunFailed catch (failed) {
      uploadOutcome = failed.outcome;
    }
    // One line per tick, whatever happened: a quiet logcat then means the
    // tick never ran, not that it ran and found nothing to say.
    debugPrint(
      'Collection service tick: ${CollectionRunner.outcomeOf(result)}, '
      'upload: $uploadOutcome',
    );
    return collectionNotificationText(result, now(), upload: upload);
  }

  try {
    return await tick().timeout(timeout);
  } on TimeoutException {
    debugPrint('Collection service tick timed out in ${stage.name}');
    await recordFailure?.call(
      CollectionOutcome.timeout,
      'The ${stage.name} step did not finish in ${timeout.inMinutes} minutes',
    );
    rethrow;
  } catch (error) {
    if (stage == CollectionTickStage.settings) {
      await recordFailure?.call(
        CollectionOutcome.error,
        '${stage.name}: ${describeRunError(error)}',
      );
    }
    rethrow;
  }
}

const _pluginWakeLockKey = 'collector.pluginWakeLockFallback';

/// Whether the running service fell back to the plugin's wake lock, held for
/// as long as it runs, because its own lock could not be reached.
Future<bool> pluginWakeLockFallback() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getBool(_pluginWakeLockKey) ?? false;
}

Future<void> setPluginWakeLockFallback(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  if (value) {
    await prefs.setBool(_pluginWakeLockKey, true);
  } else {
    await prefs.remove(_pluginWakeLockKey);
  }
}

/// What the service does when the Android half of its lock does not answer
/// (a build without it): with no lock and no alarm, readings would stop when
/// the screen goes off, and nothing would say why. It says why in the
/// validation log, once, and restarts itself with the plugin's wake lock,
/// which costs battery but keeps the readings. Returns whether the tick that
/// found out should still run: not if the service is restarting under it.
@visibleForTesting
Future<bool> fallBackToPluginWakeLock({
  required Future<bool> Function() alreadyFellBack,
  required Future<void> Function(bool value) setFellBack,
  required Future<void> Function(String detail) record,
  required Future<bool> Function() restartWithPluginLock,
}) async {
  // This is the restarted service: the plugin's lock is held.
  if (await alreadyFellBack()) return true;
  await setFellBack(true);
  // Written first: the restart ends this isolate.
  await record(
    'wake lock channel missing: restarting with the wake lock held for the '
    'whole run',
  );
  if (await restartWithPluginLock()) return false;
  await record(
    'wake lock channel missing and the restart failed: readings will stop '
    'while the phone sleeps',
  );
  return true;
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
  _CollectionTaskHandler() {
    _ticker = CollectionTicker(
      wake: _wake,
      hold: collectionWakeHold,
      runTick: _runTick,
      onWakeUnavailable: _wakeUnavailable,
    );
  }

  final _wake = CollectionWake();
  late final CollectionTicker _ticker;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) =>
      _ticker.trigger(CollectionTickTrigger.start);

  @override
  void onRepeatEvent(DateTime timestamp) =>
      unawaited(_ticker.trigger(CollectionTickTrigger.timer));

  @override
  void onReceiveData(Object data) {
    _ticker.onData(data, loadInterval: _savedInterval);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) => _wake.stop();

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

  Future<Duration> _savedInterval() async =>
      Duration(minutes: (await _freshPreferences()).intervalMinutes);

  Future<bool> _wakeUnavailable() => fallBackToPluginWakeLock(
    alreadyFellBack: pluginWakeLockFallback,
    setFellBack: setPluginWakeLockFallback,
    record: (detail) async {
      final db = AppDatabase(openAppDatabase());
      try {
        final now = DateTime.now();
        await db.recordCollectionRun(
          kind: CollectionRunKind.serviceTick,
          outcome: CollectionOutcome.error,
          detail: detail,
          startedAt: now,
          finishedAt: now,
        );
      } finally {
        await db.close();
      }
    },
    restartWithPluginLock: () async {
      await FlutterForegroundTask.updateService(
        foregroundTaskOptions: collectionTaskOptions(
          _ticker.interval.inMinutes,
          pluginWakeLock: true,
        ),
      );
      return await FlutterForegroundTask.restartService()
          is ServiceRequestSuccess;
    },
  );

  Future<void> _runTick(CollectionTicker ticker) async {
    final startedAt = DateTime.now();
    AppDatabase? opened;
    try {
      final db = opened = AppDatabase(openAppDatabase());
      final preferences = await _freshPreferences();
      await ticker.useInterval(Duration(minutes: preferences.intervalMinutes));
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
        recordFailure: (outcome, detail) => db.recordCollectionRun(
          kind: CollectionRunKind.serviceTick,
          outcome: outcome,
          detail: detail,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
        ),
      );
      if (text == null) {
        await FlutterForegroundTask.stopService();
      } else {
        await FlutterForegroundTask.updateService(notificationText: text);
        FlutterForegroundTask.sendDataToMain(collectionTickMessage);
      }
    } finally {
      await opened?.close();
    }
  }
}

@pragma('vm:entry-point')
void collectionServiceEntry() {
  FlutterForegroundTask.setTaskHandler(_CollectionTaskHandler());
}
