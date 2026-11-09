import 'package:flutter/services.dart';

// How the Collect service wakes for a tick and how long it keeps the CPU.
//
// The service used to hold a wake lock for as long as it ran: its timer does
// not count while the CPU sleeps, so the CPU was never allowed to. That lock
// was nearly all of the app's overnight battery cost. Now an alarm wakes the
// phone for each tick and the lock is held for that tick only. The Android
// half is CollectionWake.kt.

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

/// Sent to the service when its wake-up alarm fires. The same text is in
/// CollectionWake.kt.
const collectionAlarmMessage = 'collection_alarm';

/// Sent to the service by the app when the interval setting changes.
const collectionIntervalChangedMessage = 'collection_interval_changed';

/// How late the alarm may be before the repeat timer takes a tick for it.
const collectionAlarmLateGrace = Duration(minutes: 2);

/// Whether a trigger should run a tick.
///
/// While the alarm drives the ticks, the repeat timer fires at unrelated
/// moments (whenever the CPU has been awake for one interval). Each of those
/// would cost a location fix to learn that no reading is due, so they are
/// dropped unless the alarm is plainly late. An alarm that arrives right after
/// another tick (one left over from before a restart) is dropped too.
bool collectionTickDue({
  required CollectionTickTrigger trigger,
  required DateTime now,
  required DateTime? lastTickStartedAt,
  required Duration interval,
  required bool alarmDriven,
}) {
  if (trigger == CollectionTickTrigger.start || lastTickStartedAt == null) {
    return true;
  }
  final elapsed = now.difference(lastTickStartedAt);
  // The clock was set back: nothing can be said, so run.
  if (elapsed.isNegative) return true;
  return switch (trigger) {
    CollectionTickTrigger.start => true,
    CollectionTickTrigger.alarm => elapsed >= interval ~/ 2,
    CollectionTickTrigger.timer =>
      !alarmDriven || elapsed >= interval + collectionAlarmLateGrace,
  };
}

/// When the next alarm should fire after the interval changed: one interval
/// after the last tick started, or now if that has passed.
Duration collectionNextAlarmDelay({
  required DateTime now,
  required DateTime? lastTickStartedAt,
  required Duration interval,
}) {
  if (lastTickStartedAt == null) return interval;
  final sinceLast = now.difference(lastTickStartedAt);
  if (sinceLast.isNegative) return interval;
  final left = interval - sinceLast;
  return left.isNegative ? Duration.zero : left;
}

/// The wake lock and the wake-up alarm of the Collect service.
class CollectionWake {
  CollectionWake({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.wrfcoin.wrfcoin_mobile/collection_wake';

  final MethodChannel _channel;

  /// Whether the last [beginTick] set an alarm for the next tick. When false
  /// the lock stays held between ticks, as it always used to, because nothing
  /// else would wake the phone.
  bool get alarmDriven => _alarmDriven;
  bool _alarmDriven = false;

  /// Call when a tick starts. Takes the lock for at most [hold], then sets
  /// the alarm for the next tick. If Android will not set an exact alarm (on
  /// Android 12 and later that needs the app to be let off battery limits),
  /// the lock is kept with no time limit instead, so readings never depend on
  /// the alarm. Returns [alarmDriven].
  Future<bool> beginTick({
    required Duration interval,
    required Duration hold,
  }) async {
    try {
      await _channel.invokeMethod<void>('acquire', {
        'timeoutMs': hold.inMilliseconds,
      });
      _alarmDriven = await _schedule(interval, hold);
      if (!_alarmDriven) {
        await _channel.invokeMethod<void>('acquire', {'timeoutMs': null});
      }
    } on MissingPluginException {
      _alarmDriven = false;
    } on PlatformException {
      _alarmDriven = false;
    }
    return _alarmDriven;
  }

  /// Call when a tick ends, however it ended. Gives the lock back if an alarm
  /// will bring the next tick.
  Future<void> endTick() async {
    if (_alarmDriven) await release();
  }

  /// Call when an alarm arrived and no tick will run for it. The alarm took
  /// the lock with a time limit: give it back, or, if the lock is the kind
  /// held between ticks, take the time limit off again.
  Future<void> dropTick() async {
    if (_alarmDriven) return release();
    try {
      await _channel.invokeMethod<void>('acquire', {'timeoutMs': null});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Moves the alarm, when the alarm is what drives the ticks.
  Future<void> reschedule({
    required Duration delay,
    required Duration hold,
  }) async {
    if (!_alarmDriven) return;
    try {
      await _schedule(delay, hold);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> release() => _quietly('release');

  /// The service is stopping: no alarm, no lock.
  Future<void> stop() async {
    await _quietly('cancelAlarm');
    await _quietly('release');
    _alarmDriven = false;
  }

  Future<bool> _schedule(Duration delay, Duration hold) async =>
      await _channel.invokeMethod<bool>('scheduleAlarm', {
        'delayMs': delay.inMilliseconds,
        'holdMs': hold.inMilliseconds,
      }) ??
      false;

  Future<void> _quietly(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
