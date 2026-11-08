import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/background/sensor_worker.dart';
import '../../../services/notifications/push_service.dart';
import 'ntfy_poller.dart';
import 'payout_alert_style.dart';

final payoutDeviceProvider = Provider<PayoutDevice>(
  (ref) => PayoutDevice(ref.watch(pushServiceProvider)),
);

/// What turning notifications on means on this phone: the OS permission, the
/// stored topic and the periodic check.
class PayoutDevice {
  PayoutDevice(this._push);

  final PushService _push;
  final _store = const NtfyDeviceStore();
  final _styles = const PayoutAlertStyleStore();

  Future<PayoutAlertStyle> alertStyle() => _styles.load();
  Future<void> setAlertStyle(PayoutAlertStyle style) => _styles.save(style);

  /// Android's own page for this app's notifications.
  Future<bool> openSystemSettings() => _push.openSystemNotificationSettings();

  Future<bool> requestPermission() => _push.requestPermission();
  Future<String?> topic() => _store.topic();
  String newTopic() => suggestNtfyTopic();

  /// Reads from this moment on, so old messages on a reused topic stay quiet.
  Future<void> enable({required String topic, required String server}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _store.save(topic: topic, server: server, since: '$now');
    await registerPayoutPollWorker();
  }

  Future<void> disable() async {
    await cancelPayoutPollWorker();
    await _store.clear();
  }

  /// Checks now, so a test appears without waiting for the periodic check.
  Future<int> checkNow() =>
      NtfyPoller(store: _store, show: _push.showPayoutNotification).pollOnce();
}
