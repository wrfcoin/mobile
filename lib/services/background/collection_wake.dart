import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

// How the Collect service wakes for a tick and how long it keeps the CPU.
//
// The service used to hold a wake lock for as long as it ran: its timer does
// not count while the CPU sleeps, so the CPU was never allowed to. That lock
// was nearly all of the app's overnight battery cost. Now an alarm wakes the
// phone for each tick and the lock is held for that tick only. The Android
// half, CollectionWake.kt, owns the lock and decides when it may be given
// back; this half only says when a tick starts and ends.

/// What made the service consider a tick.
enum CollectionTickTrigger {
  /// The service started, or Android restarted it.
  start,

  /// The wake-up alarm fired.
  alarm,

  /// The service's own repeat timer fired. It only counts time the CPU is
  /// awake, so with the alarm working it is a backstop, not the clock.
  timer,
}

/// Sent to the service when its wake-up alarm fires, followed by a colon and
/// the alarm's number. The same text is in CollectionWake.kt.
const collectionAlarmMessage = 'collection_alarm';

/// Sent to the service by the app when the interval setting changes.
const collectionIntervalChangedMessage = 'collection_interval_changed';

/// How late the alarm may be before the repeat timer takes a tick for it.
const collectionAlarmLateGrace = Duration(minutes: 2);

/// The number of the alarm in a message from the Android half, or null if
/// the message is not an alarm.
int? collectionAlarmSeq(Object data) {
  if (data is! String) return null;
  if (data == collectionAlarmMessage) return 0;
  if (!data.startsWith('$collectionAlarmMessage:')) return null;
  return int.tryParse(data.substring(collectionAlarmMessage.length + 1));
}

/// Whether a repeat timer event should run a tick while the alarm drives the
/// ticks. The timer fires at unrelated moments (whenever the CPU has been
/// awake for one interval), and each would cost a location fix to learn that
/// no reading is due, so they are dropped unless the alarm is plainly late.
///
/// The times are Android's time since boot, which counts sleep and cannot be
/// set by anyone. With either unknown the answer is yes.
bool collectionTimerTickDue({
  required int? nowMs,
  required int? lastTickMs,
  required Duration interval,
}) {
  if (nowMs == null || lastTickMs == null || nowMs < lastTickMs) return true;
  return nowMs - lastTickMs >=
      (interval + collectionAlarmLateGrace).inMilliseconds;
}

/// When the next alarm should fire after the interval changed: one interval
/// after the last tick started, or now if that has passed.
Duration collectionNextAlarmDelay({
  required int? nowMs,
  required int? lastTickMs,
  required Duration interval,
}) {
  if (nowMs == null || lastTickMs == null || nowMs < lastTickMs) {
    return interval;
  }
  final left = interval - Duration(milliseconds: nowMs - lastTickMs);
  return left.isNegative ? Duration.zero : left;
}

/// What the Android half said when a tick began.
class CollectionWakeBegin {
  const CollectionWakeBegin({
    required this.armed,
    required this.elapsedRealtimeMs,
    required this.alarmSeq,
  }) : available = true;

  /// The Android half did not answer: there is no lock and no alarm.
  const CollectionWakeBegin.unavailable()
    : available = false,
      armed = false,
      elapsedRealtimeMs = null,
      alarmSeq = 0;

  final bool available;

  /// Whether an alarm is set for the next tick.
  final bool armed;

  /// Android's time since boot when the tick began.
  final int? elapsedRealtimeMs;

  /// The number of the last alarm delivered before the tick began.
  final int alarmSeq;
}

/// The wake lock and the wake-up alarm of the Collect service.
class CollectionWake {
  CollectionWake({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.wrfcoin.wrfcoin_mobile/collection_wake';

  final MethodChannel _channel;

  /// Whether an alarm is set for the next tick, as last heard from Android.
  /// When false the lock stays held between ticks, as it always used to,
  /// because nothing else would wake the phone.
  bool get alarmDriven => _alarmDriven;
  bool _alarmDriven = false;

  /// Call when a tick starts. Android takes the lock for at most [hold] and
  /// sets the alarm for the next tick, or, if it may not set an exact alarm
  /// (on Android 12 and later that needs the app to be let off battery
  /// limits), keeps the lock with no time limit. Never throws.
  Future<CollectionWakeBegin> beginTick({
    required Duration interval,
    required Duration hold,
  }) async {
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>(
        'beginTick',
        {'intervalMs': interval.inMilliseconds, 'holdMs': hold.inMilliseconds},
      );
      _alarmDriven = answer?['armed'] == true;
      return CollectionWakeBegin(
        armed: _alarmDriven,
        elapsedRealtimeMs: (answer?['elapsedRealtimeMs'] as num?)?.toInt(),
        alarmSeq: (answer?['alarmSeq'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      _alarmDriven = false;
      return const CollectionWakeBegin.unavailable();
    } on PlatformException {
      _alarmDriven = false;
      return const CollectionWakeBegin.unavailable();
    }
  }

  /// Call when a tick ends, however it ended. Android gives the lock back
  /// only if an alarm is still set for the next tick; otherwise it keeps it.
  /// [seenAlarmSeq] is the last alarm this side has heard of, so that an
  /// alarm delivered a moment ago keeps the lock for its own tick.
  Future<void> endTick({required int seenAlarmSeq}) async {
    try {
      _alarmDriven =
          await _channel.invokeMethod<bool>('endTick', {
            'seenAlarmSeq': seenAlarmSeq,
          }) ??
          false;
    } on MissingPluginException {
      _alarmDriven = false;
    } on PlatformException {
      _alarmDriven = false;
    }
  }

  /// Moves the next alarm, when alarms drive the ticks. Every alarm after it
  /// comes one [interval] after the one before.
  Future<void> reschedule({
    required Duration delay,
    required Duration interval,
    required Duration hold,
  }) async {
    if (!_alarmDriven) return;
    try {
      _alarmDriven =
          await _channel.invokeMethod<bool>('reschedule', {
            'delayMs': delay.inMilliseconds,
            'intervalMs': interval.inMilliseconds,
            'holdMs': hold.inMilliseconds,
          }) ??
          false;
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Android's time since boot, or null if it cannot be asked.
  Future<int?> elapsedRealtimeMs() async {
    try {
      return await _channel.invokeMethod<int>('elapsedRealtime');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// The service is stopping: no alarm, no lock.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Nothing to stop.
    } on PlatformException {
      // Android clears both itself when the service's engine goes.
    }
    _alarmDriven = false;
  }
}

/// Decides which triggers run a tick, and brackets each tick with the lock.
///
/// At most one tick runs at a time. An alarm always runs one unless one is
/// running: it is never dropped on a clock reading. Android sets the next
/// alarm itself when one fires, so a dropped alarm does not break the chain.
class CollectionTicker {
  CollectionTicker({
    required this._wake,
    required this._runTick,
    required this.hold,
    this._onWakeUnavailable,
    this._interval = const Duration(minutes: 15),
  });

  final CollectionWake _wake;

  /// One tick's work. It may throw; it should call [useInterval] once it has
  /// read the settings.
  final Future<void> Function(CollectionTicker ticker) _runTick;

  /// Called the first time the Android half does not answer. Returns whether
  /// this tick should still run.
  final Future<bool> Function()? _onWakeUnavailable;

  /// The longest the lock is held for one tick.
  final Duration hold;

  bool get ticking => _ticking;
  bool _ticking = false;
  bool _checkingTimer = false;
  bool _toldUnavailable = false;
  int? _lastTickMs;
  int _seenAlarmSeq = 0;

  Duration get interval => _interval;
  Duration _interval;

  /// A message for the service. Returns whether it was one of ours.
  bool onData(Object data, {Future<Duration> Function()? loadInterval}) {
    final seq = collectionAlarmSeq(data);
    if (seq != null) {
      _seenAlarmSeq = math.max(_seenAlarmSeq, seq);
      unawaited(trigger(CollectionTickTrigger.alarm));
      return true;
    }
    if (data == collectionIntervalChangedMessage) {
      if (loadInterval != null) unawaited(_reloadInterval(loadInterval));
      return true;
    }
    return false;
  }

  Future<void> trigger(CollectionTickTrigger trigger) async {
    // The running tick ends the lock. Android has set the next alarm.
    if (_ticking) return;
    if (trigger == CollectionTickTrigger.timer && _wake.alarmDriven) {
      if (_checkingTimer) return;
      _checkingTimer = true;
      int? nowMs;
      try {
        nowMs = await _wake.elapsedRealtimeMs();
      } finally {
        _checkingTimer = false;
      }
      // An alarm may have started a tick while Android was asked the time.
      if (_ticking) return;
      if (!collectionTimerTickDue(
        nowMs: nowMs,
        lastTickMs: _lastTickMs,
        interval: _interval,
      )) {
        return;
      }
    }
    _ticking = true;
    try {
      if (await _begin()) await _runTick(this);
    } catch (error) {
      // Stay alive for the next tick. The reason is in the validation log.
      debugPrint('Collection service tick failed: ${error.runtimeType}');
    } finally {
      _ticking = false;
      await _wake.endTick(seenAlarmSeq: _seenAlarmSeq);
    }
  }

  /// The interval now in the settings. If it changed, the alarm for the next
  /// tick is set again with it.
  Future<void> useInterval(Duration interval) async {
    if (interval == _interval) return;
    _interval = interval;
    if (_ticking) await _begin();
  }

  Future<bool> _begin() async {
    final begin = await _wake.beginTick(interval: _interval, hold: hold);
    if (!begin.available) {
      if (_toldUnavailable) return true;
      _toldUnavailable = true;
      return await _onWakeUnavailable?.call() ?? true;
    }
    _lastTickMs = begin.elapsedRealtimeMs ?? _lastTickMs;
    _seenAlarmSeq = math.max(_seenAlarmSeq, begin.alarmSeq);
    return true;
  }

  Future<void> _reloadInterval(Future<Duration> Function() load) async {
    try {
      final interval = await load();
      if (interval == _interval) return;
      _interval = interval;
      // A running tick's next alarm is moved here too; Android sets every
      // later one from the interval, never from this delay.
      if (!_wake.alarmDriven) return;
      await _wake.reschedule(
        delay: collectionNextAlarmDelay(
          nowMs: await _wake.elapsedRealtimeMs(),
          lastTickMs: _lastTickMs,
          interval: interval,
        ),
        interval: interval,
        hold: hold,
      );
    } catch (error) {
      // The next tick sets the alarm from the saved interval anyway.
      debugPrint('Collection interval change failed: ${error.runtimeType}');
    }
  }
}
