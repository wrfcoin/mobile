import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a payout notice gets your attention. Every style still shows the
/// notice in the shade; only sound and vibration change.
enum PayoutAlertStyle {
  sound('Sound', 'Sound and vibration, like other apps.'),
  vibrate('Vibrate only', 'No sound.'),
  silent('Silent', 'Shown in the notification shade, no sound or vibration.');

  const PayoutAlertStyle(this.label, this.detail);

  final String label;
  final String detail;

  static PayoutAlertStyle fromName(String? name) => PayoutAlertStyle.values
      .firstWhere((s) => s.name == name, orElse: () => defaultStyle);

  /// New installs keep the sound the app always had.
  static const defaultStyle = PayoutAlertStyle.sound;
}

/// The choice is kept in SharedPreferences because the Workmanager isolate,
/// which posts the notices, reads it too.
class PayoutAlertStyleStore {
  const PayoutAlertStyleStore();

  static const _key = 'payout_alert_style';

  Future<PayoutAlertStyle> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Another isolate may have written it since this one last read.
    await prefs.reload();
    return PayoutAlertStyle.fromName(prefs.getString(_key));
  }

  Future<void> save(PayoutAlertStyle style) async {
    await (await SharedPreferences.getInstance()).setString(_key, style.name);
  }
}

/// Android cannot change a channel's sound or vibration once it exists, so
/// each style has its own channel. Sound keeps the original channel id, so a
/// phone that already set that channel up in system settings keeps it.
const payoutChannelIds = {
  PayoutAlertStyle.sound: 'wrfcoin_payouts',
  PayoutAlertStyle.vibrate: 'wrfcoin_payouts_vibrate',
  PayoutAlertStyle.silent: 'wrfcoin_payouts_silent',
};

/// The Android details for one payout notice. [alert] false posts it silently
/// whatever the style: one check that finds several payouts alerts once.
AndroidNotificationDetails payoutNotificationDetails(
  PayoutAlertStyle style, {
  bool alert = true,
}) {
  final channelId = payoutChannelIds[style]!;
  return switch (style) {
    PayoutAlertStyle.sound => AndroidNotificationDetails(
      channelId,
      'Payouts',
      channelDescription: 'When your wallet is paid',
      importance: Importance.defaultImportance,
      silent: !alert,
    ),
    PayoutAlertStyle.vibrate => AndroidNotificationDetails(
      channelId,
      'Payouts (vibrate only)',
      channelDescription: 'When your wallet is paid. Vibrates, no sound.',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: true,
      silent: !alert,
    ),
    PayoutAlertStyle.silent => AndroidNotificationDetails(
      channelId,
      'Payouts (silent)',
      channelDescription:
          'When your wallet is paid. Shown with no sound or vibration.',
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
      silent: true,
    ),
  };
}
