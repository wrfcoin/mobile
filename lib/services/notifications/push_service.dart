import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notifications/data/payout_alert_style.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService();
});

class PushService {
  PushService({this.alertStyles = const PayoutAlertStyleStore()});

  final PayoutAlertStyleStore alertStyles;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
    _initialized = true;
  }

  /// Asks the OS to allow notifications (Android 13+, iOS). True when allowed.
  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  /// Payouts get their own channels, so they can be silenced apart from
  /// weather. The channel follows the alert style chosen in the app; [alert]
  /// false posts silently (the second and later notices of one check).
  Future<void> showPayoutNotification({
    required int id,
    required String title,
    required String body,
    bool alert = true,
  }) async {
    await initialize();
    final android = payoutNotificationDetails(
      await alertStyles.load(),
      alert: alert,
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: android),
    );
  }

  /// This app's page in Android's notification settings. False when the
  /// platform has none.
  Future<bool> openSystemNotificationSettings() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    return await android.openAppNotificationSettings() ?? false;
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'wrfcoin_alerts',
      'Weather Alerts',
      channelDescription: 'WRFCoin weather and data alerts',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }
}
