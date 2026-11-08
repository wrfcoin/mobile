// Which channel and sound settings a payout notice is posted with.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/notifications/data/payout_alert_style.dart';

void main() {
  group('store', () {
    const store = PayoutAlertStyleStore();

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a new install keeps the sound it always had', () async {
      expect(await store.load(), PayoutAlertStyle.sound);
    });

    test('a saved choice is read back', () async {
      await store.save(PayoutAlertStyle.vibrate);
      expect(await store.load(), PayoutAlertStyle.vibrate);
      await store.save(PayoutAlertStyle.silent);
      expect(await store.load(), PayoutAlertStyle.silent);
    });

    test('an unknown stored value falls back to the default', () async {
      SharedPreferences.setMockInitialValues({'payout_alert_style': 'loud'});
      expect(await store.load(), PayoutAlertStyle.sound);
    });
  });

  group('details', () {
    test('each style has its own channel; sound keeps the original id', () {
      final ids = {
        for (final style in PayoutAlertStyle.values)
          payoutNotificationDetails(style).channelId,
      };
      expect(ids, hasLength(PayoutAlertStyle.values.length));
      expect(
        payoutNotificationDetails(PayoutAlertStyle.sound).channelId,
        'wrfcoin_payouts',
      );
    });

    test('sound: plays and vibrates', () {
      final d = payoutNotificationDetails(PayoutAlertStyle.sound);
      expect(d.playSound, isTrue);
      expect(d.enableVibration, isTrue);
      expect(d.silent, isFalse);
      expect(d.importance, Importance.defaultImportance);
    });

    test('vibrate only: vibrates, never a sound', () {
      final d = payoutNotificationDetails(PayoutAlertStyle.vibrate);
      expect(d.playSound, isFalse);
      expect(d.enableVibration, isTrue);
      expect(d.silent, isFalse);
    });

    test('silent: shown, no sound, no vibration', () {
      final d = payoutNotificationDetails(PayoutAlertStyle.silent);
      expect(d.playSound, isFalse);
      expect(d.enableVibration, isFalse);
      expect(d.silent, isTrue);
      expect(d.importance, Importance.low);
    });

    test('a notice that should not alert is silent in every style', () {
      for (final style in PayoutAlertStyle.values) {
        expect(
          payoutNotificationDetails(style, alert: false).silent,
          isTrue,
          reason: style.name,
        );
      }
    });
  });
}
