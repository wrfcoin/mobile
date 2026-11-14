import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// When Android or the phone maker stops the collection service while Collect
// is on (Samsung's Device Care restarts the system at night, for one), nothing
// can start it again from the background: Android does not let a location
// service start unless the app is on screen. The WorkManager job cannot take
// readings either, because a background app gets no barometer data. So the
// job tells the user once, and opening the app starts the service again.

/// The id of the "collection stopped" notice. Not used by any other notice.
const collectionStoppedNoticeId = 8881;

const _noticeShownKey = 'collector.stoppedNoticeShown';

const collectionStoppedNoticeTitle = 'Weather collection stopped';
const collectionStoppedNoticeBody =
    'Your phone stopped it in the background. Tap to start it again.';

/// Whether the collection service is running in this app. Null when this
/// platform has no service or the plugin cannot say: then nothing changes.
Future<bool?> collectionServiceRunning() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    return await FlutterForegroundTask.isRunningService;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// What the job does when it starts with Collect on. Returns true when the
/// service is known to be stopped: the job then takes no reading, since it
/// would wait 5 s for a barometer that sends nothing to a background app.
///
/// The notice is posted once per stop. The flag is cleared when the service
/// is seen running again (here, or by [clearCollectionStoppedNotice] when the
/// app starts it).
@visibleForTesting
Future<bool> checkCollectionServiceStopped({
  required Future<bool?> Function() serviceRunning,
  required Future<bool> Function() noticeShown,
  required Future<void> Function(bool shown) setNoticeShown,
  required Future<void> Function() showNotice,
  required Future<void> Function() cancelNotice,
}) async {
  final running = await serviceRunning();
  if (running == null) return false;
  if (running) {
    if (await noticeShown()) {
      await setNoticeShown(false);
      await cancelNotice();
    }
    return false;
  }
  if (!await noticeShown()) {
    // Saved first: a second job must not post it again if this one dies.
    await setNoticeShown(true);
    await showNotice();
  }
  return true;
}

/// [checkCollectionServiceStopped] with the real plugin, preferences and
/// notification.
Future<bool> collectionServiceStopped() => checkCollectionServiceStopped(
  serviceRunning: collectionServiceRunning,
  noticeShown: _noticeShown,
  setNoticeShown: _setNoticeShown,
  showNotice: _showNotice,
  cancelNotice: _cancelNotice,
);

/// Called when the service starts or Collect is turned off: removes the notice
/// and lets the next stop post it again.
Future<void> clearCollectionStoppedNotice() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  // Never in the way of starting or stopping the service.
  try {
    if (!await _noticeShown()) return;
    await _setNoticeShown(false);
    await _cancelNotice();
  } on MissingPluginException {
    return;
  } on PlatformException {
    return;
  }
}

Future<bool> _noticeShown() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getBool(_noticeShownKey) ?? false;
}

Future<void> _setNoticeShown(bool shown) async {
  final prefs = await SharedPreferences.getInstance();
  if (shown) {
    await prefs.setBool(_noticeShownKey, true);
  } else {
    await prefs.remove(_noticeShownKey);
  }
}

Future<FlutterLocalNotificationsPlugin?> _notifications() async {
  final plugin = FlutterLocalNotificationsPlugin();
  try {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    return plugin;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// The notice itself. Tapping it opens the app, which restarts the service.
@visibleForTesting
const collectionStoppedNoticeDetails = AndroidNotificationDetails(
  'wrfcoin_collection_stopped',
  'Collection stopped',
  channelDescription:
      'Tells you when the phone stopped weather collection in the background.',
  importance: Importance.defaultImportance,
  priority: Priority.defaultPriority,
  onlyAlertOnce: true,
  autoCancel: true,
);

Future<void> _showNotice() async {
  final plugin = await _notifications();
  try {
    await plugin?.show(
      id: collectionStoppedNoticeId,
      title: collectionStoppedNoticeTitle,
      body: collectionStoppedNoticeBody,
      notificationDetails: const NotificationDetails(
        android: collectionStoppedNoticeDetails,
      ),
    );
  } on PlatformException {
    return;
  }
}

Future<void> _cancelNotice() async {
  final plugin = await _notifications();
  try {
    await plugin?.cancel(id: collectionStoppedNoticeId);
  } on PlatformException {
    return;
  }
}
