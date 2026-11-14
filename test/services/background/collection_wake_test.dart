// When the Collect service ticks, and when its wake lock may be given back.
//
// The ticker is run here against a small model of the Android half
// (CollectionWake.kt), which keeps the same rule: the lock is only given back
// while an alarm is set. The Android half itself is tested on the JVM in
// android/app/src/test. The battery saving still needs a night on a phone.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/background/collection_service.dart';
import 'package:wrfcoin_mobile/services/background/collection_wake.dart';

const _interval = Duration(minutes: 15);
const _hold = Duration(minutes: 11);
final _minute = const Duration(minutes: 1).inMilliseconds;

/// What CollectionWake.kt does, without Android.
class _FakeAndroid {
  bool canExact = true;
  bool armed = false;

  /// 'none', 'timed' (one tick) or 'held' (no time limit).
  String lock = 'none';
  int seq = 0;
  int nowMs = 1000000;
  int? alarmAtMs;
  int? alarmIntervalMs;
  final calls = <String>[];

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
    calls.add(call.method);
    switch (call.method) {
      case 'beginTick':
        lock = 'timed';
        _armOrHold(args['intervalMs']! as int, args['intervalMs']! as int);
        return {'armed': armed, 'elapsedRealtimeMs': nowMs, 'alarmSeq': seq};
      case 'endTick':
        if (!armed || !canExact) {
          _hold();
          return false;
        }
        if (seq <= (args['seenAlarmSeq']! as int)) lock = 'none';
        return true;
      case 'reschedule':
        if (!armed) return false;
        _armOrHold(args['delayMs']! as int, args['intervalMs']! as int);
        return armed;
      case 'elapsedRealtime':
        return nowMs;
      case 'stop':
        armed = false;
        alarmAtMs = null;
        lock = 'none';
        return null;
    }
    throw MissingPluginException();
  }

  void _hold() {
    armed = false;
    alarmAtMs = null;
    lock = 'held';
  }

  void _armOrHold(int delayMs, int intervalMs) {
    if (!canExact) return _hold();
    armed = true;
    alarmAtMs = nowMs + delayMs;
    alarmIntervalMs = intervalMs;
  }

  /// The alarm receiver. Returns its message for the service.
  String fireAlarm() {
    nowMs = alarmAtMs ?? nowMs;
    lock = 'timed';
    seq++;
    _armOrHold(alarmIntervalMs!, alarmIntervalMs!);
    return '$collectionAlarmMessage:$seq';
  }
}

/// Lets queued channel replies and their continuations run.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(CollectionWake.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeAndroid android;

  setUp(() {
    android = _FakeAndroid();
    messenger.setMockMethodCallHandler(channel, android.handle);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('alarm message', () {
    test('carries the alarm number', () {
      expect(collectionAlarmSeq('collection_alarm:7'), 7);
      expect(collectionAlarmSeq('collection_alarm'), 0);
      expect(collectionAlarmSeq('collection_alarm:x'), isNull);
      expect(collectionAlarmSeq(collectionIntervalChangedMessage), isNull);
      expect(collectionAlarmSeq(42), isNull);
    });
  });

  group('collectionTimerTickDue', () {
    bool due(int sinceLastMinutes) => collectionTimerTickDue(
      nowMs: 5000 + sinceLastMinutes * _minute,
      lastTickMs: 5000,
      interval: _interval,
    );

    test('only covers an alarm that is plainly late', () {
      expect(due(7), isFalse);
      expect(due(15), isFalse);
      expect(due(17), isTrue);
    });

    test('a late alarm is covered before a 20 minute gap', () {
      expect(
        _interval + collectionAlarmLateGrace,
        lessThan(const Duration(minutes: 20)),
      );
    });

    test('runs when the time is unknown', () {
      for (final (now, last) in [(null, 5000), (5000, null), (4000, 5000)]) {
        expect(
          collectionTimerTickDue(
            nowMs: now,
            lastTickMs: last,
            interval: _interval,
          ),
          isTrue,
        );
      }
    });
  });

  group('collectionNextAlarmDelay', () {
    Duration delay(int sinceLastMinutes, int intervalMinutes) =>
        collectionNextAlarmDelay(
          nowMs: 5000 + sinceLastMinutes * _minute,
          lastTickMs: 5000,
          interval: Duration(minutes: intervalMinutes),
        );

    test('counts the new interval from the last tick', () {
      expect(delay(5, 30), const Duration(minutes: 25));
    });

    test('is now when the new interval has already passed', () {
      expect(delay(40, 15), Duration.zero);
    });

    test('is one interval when the last tick is unknown', () {
      expect(
        collectionNextAlarmDelay(
          nowMs: 5000,
          lastTickMs: null,
          interval: _interval,
        ),
        _interval,
      );
    });
  });

  group('CollectionTicker', () {
    late int runs;
    Completer<void>? gate;
    Object? failure;
    Duration? settingsInterval;

    CollectionTicker ticker({Future<bool> Function()? onWakeUnavailable}) =>
        CollectionTicker(
          wake: CollectionWake(),
          hold: _hold,
          onWakeUnavailable: onWakeUnavailable,
          runTick: (ticker) async {
            runs++;
            if (settingsInterval != null) {
              await ticker.useInterval(settingsInterval!);
            }
            await gate?.future;
            if (failure != null) throw failure!;
          },
        );

    setUp(() {
      runs = 0;
      gate = null;
      failure = null;
      settingsInterval = null;
    });

    test('a tick takes the lock, sets the alarm, runs, lets go', () async {
      final t = ticker();
      await t.trigger(CollectionTickTrigger.start);
      expect(runs, 1);
      expect(android.calls, ['beginTick', 'endTick']);
      expect(android.lock, 'none');
      expect(android.armed, isTrue);
      expect(android.alarmAtMs, android.nowMs + _interval.inMilliseconds);
    });

    test('the lock is held while the tick runs', () async {
      gate = Completer<void>();
      final t = ticker();
      final running = t.trigger(CollectionTickTrigger.start);
      await _settle();
      expect(t.ticking, isTrue);
      expect(android.lock, 'timed');
      gate!.complete();
      await running;
      expect(android.lock, 'none');
    });

    test('every alarm runs a tick: none is dropped on a clock', () async {
      final t = ticker();
      await t.trigger(CollectionTickTrigger.start);
      // Two alarms a moment apart, as after a clock change or a restart.
      expect(t.onData(android.fireAlarm()), isTrue);
      await _settle();
      expect(t.onData(android.fireAlarm()), isTrue);
      await _settle();
      expect(runs, 3);
      expect(android.lock, 'none');
      expect(android.armed, isTrue);
    });

    test('an alarm during a tick is dropped and the chain goes on', () async {
      gate = Completer<void>();
      final t = ticker();
      final running = t.trigger(CollectionTickTrigger.start);
      await _settle();
      t.onData(android.fireAlarm());
      await _settle();
      expect(runs, 1);
      // The receiver set the next alarm and renewed the lock.
      expect(android.lock, 'timed');
      gate!.complete();
      await running;
      expect(android.lock, 'none');
      expect(android.armed, isTrue);
    });

    test('battery exemption removed mid-tick: the lock is kept', () async {
      gate = Completer<void>();
      final t = ticker();
      final running = t.trigger(CollectionTickTrigger.start);
      await _settle();
      android.canExact = false;
      // The alarm fires; its re-arm is refused.
      t.onData(android.fireAlarm());
      await _settle();
      gate!.complete();
      await running;
      expect(android.armed, isFalse);
      expect(android.lock, 'held');
      // And the repeat timer drives the ticks again.
      await t.trigger(CollectionTickTrigger.timer);
      expect(runs, 2);
      expect(android.lock, 'held');
    });

    test('exemption removed between ticks: the tick ends holding', () async {
      final t = ticker();
      await t.trigger(CollectionTickTrigger.start);
      android.canExact = false;
      t.onData(android.fireAlarm());
      await _settle();
      expect(runs, 2);
      expect(android.lock, 'held');
    });

    test('exemption given back: the held lock is released again', () async {
      android.canExact = false;
      final t = ticker();
      await t.trigger(CollectionTickTrigger.start);
      expect(android.lock, 'held');
      android.canExact = true;
      await t.trigger(CollectionTickTrigger.timer);
      expect(android.lock, 'none');
      expect(android.armed, isTrue);
    });

    test('interval changed during a long tick: alarm still set', () async {
      gate = Completer<void>();
      final t = ticker();
      final running = t.trigger(CollectionTickTrigger.start);
      await _settle();
      android.nowMs += 20 * _minute;
      t.onData(
        collectionIntervalChangedMessage,
        loadInterval: () async => const Duration(minutes: 30),
      );
      await _settle();
      // 30 minutes from the tick's start, and 30 minutes after that.
      expect(android.alarmAtMs, android.nowMs + 10 * _minute);
      expect(android.alarmIntervalMs, 30 * _minute);
      gate!.complete();
      await running;
      expect(android.lock, 'none');
      expect(android.armed, isTrue);
    });

    test('interval shortened past due during a tick', () async {
      gate = Completer<void>();
      final t = ticker();
      t.onData(
        collectionIntervalChangedMessage,
        loadInterval: () async => const Duration(minutes: 60),
      );
      final running = t.trigger(CollectionTickTrigger.start);
      await _settle();
      android.nowMs += 20 * _minute;
      t.onData(
        collectionIntervalChangedMessage,
        loadInterval: () async => _interval,
      );
      await _settle();
      // Due at once: it fires during the tick and is dropped, but the
      // receiver set the one after it from the interval, not from zero.
      expect(android.alarmAtMs, android.nowMs);
      t.onData(android.fireAlarm());
      await _settle();
      expect(android.alarmAtMs, android.nowMs + _interval.inMilliseconds);
      gate!.complete();
      await running;
      expect(runs, 1);
      expect(android.lock, 'none');
      expect(android.armed, isTrue);
    });

    test('a tick that reads a new interval sets its alarm again', () async {
      settingsInterval = const Duration(minutes: 30);
      final t = ticker();
      await t.trigger(CollectionTickTrigger.start);
      expect(android.calls, ['beginTick', 'beginTick', 'endTick']);
      expect(android.alarmIntervalMs, 30 * _minute);
      expect(t.interval, const Duration(minutes: 30));
    });

    test('an alarm not yet heard of keeps the lock for its tick', () async {
      gate = Completer<void>();
      final t = ticker();
      final running = t.trigger(CollectionTickTrigger.start);
      await _settle();
      // Delivered on the Android side; its message has not arrived.
      final message = android.fireAlarm();
      gate!.complete();
      await running;
      expect(android.lock, 'timed');
      t.onData(message);
      await _settle();
      expect(runs, 2);
      expect(android.lock, 'none');
    });

    test('with the alarm working the repeat timer is a backstop', () async {
      final t = ticker();
      await t.trigger(CollectionTickTrigger.start);
      android.nowMs += 7 * _minute;
      await t.trigger(CollectionTickTrigger.timer);
      expect(runs, 1);
      expect(android.calls.last, 'elapsedRealtime');
      android.nowMs += 10 * _minute;
      await t.trigger(CollectionTickTrigger.timer);
      expect(runs, 2);
    });

    test('an alarm is not lost while the timer asks the time', () async {
      final t = ticker();
      await t.trigger(CollectionTickTrigger.start);
      final timer = t.trigger(CollectionTickTrigger.timer);
      t.onData(android.fireAlarm());
      await timer;
      await _settle();
      expect(runs, 2);
      expect(android.lock, 'none');
    });

    test('with no exact alarm every timer tick runs, as before', () async {
      android.canExact = false;
      final t = ticker();
      await t.trigger(CollectionTickTrigger.start);
      await t.trigger(CollectionTickTrigger.timer);
      await t.trigger(CollectionTickTrigger.timer);
      expect(runs, 3);
      expect(android.lock, 'held');
      expect(android.calls, isNot(contains('elapsedRealtime')));
    });

    test('a tick that throws does not stick or keep the lock', () async {
      failure = StateError('database would not open');
      final t = ticker();
      await t.trigger(CollectionTickTrigger.start);
      expect(t.ticking, isFalse);
      expect(android.lock, 'none');
      failure = null;
      t.onData(android.fireAlarm());
      await _settle();
      expect(runs, 2);
      expect(android.lock, 'none');
    });

    test('no Android half: said once, and the tick can be skipped', () async {
      messenger.setMockMethodCallHandler(channel, null);
      var told = 0;
      final t = ticker(
        onWakeUnavailable: () async {
          told++;
          return false;
        },
      );
      await t.trigger(CollectionTickTrigger.start);
      expect(told, 1);
      expect(runs, 0);
      expect(t.ticking, isFalse);
      // Later ticks run on the repeat timer, without saying it again.
      await t.trigger(CollectionTickTrigger.timer);
      expect(told, 1);
      expect(runs, 1);
    });
  });

  group('fallBackToPluginWakeLock', () {
    late bool fellBack;
    late List<String> rows;
    late int restarts;

    Future<bool> fall({required bool restartWorks}) => fallBackToPluginWakeLock(
      alreadyFellBack: () async => fellBack,
      setFellBack: (value) async => fellBack = value,
      record: (detail) async => rows.add(detail),
      restartWithPluginLock: () async {
        restarts++;
        return restartWorks;
      },
    );

    setUp(() {
      fellBack = false;
      rows = [];
      restarts = 0;
    });

    test(
      'says why, then restarts with the old lock; tick is skipped',
      () async {
        expect(await fall(restartWorks: true), isFalse);
        expect(fellBack, isTrue);
        expect(restarts, 1);
        expect(rows, hasLength(1));
        expect(rows.single, contains('wake lock channel missing'));
      },
    );

    test('the restarted service does not restart again', () async {
      fellBack = true;
      expect(await fall(restartWorks: true), isTrue);
      expect(restarts, 0);
      expect(rows, isEmpty);
    });

    test('a failed restart is said too, and the tick still runs', () async {
      expect(await fall(restartWorks: false), isTrue);
      expect(rows, hasLength(2));
      expect(rows.last, contains('restart failed'));
    });
  });

  group('service options', () {
    test('the plugin no longer holds a wake lock for the whole run', () {
      final options = collectionTaskOptions(15);
      expect(options.allowWakeLock, isFalse);
      expect(options.allowWifiLock, isFalse);
      expect(options.allowAutoRestart, isTrue);
      expect(options.autoRunOnBoot, isFalse);
      expect(options.eventAction.toJson()['taskEventInterval'], 900000);
    });

    test('except as the fallback', () {
      expect(
        collectionTaskOptions(15, pluginWakeLock: true).allowWakeLock,
        isTrue,
      );
    });

    test('the lock outlasts a tick, but not by much', () {
      expect(collectionWakeHold, greaterThan(collectionTickTimeout));
      expect(collectionWakeHold, lessThan(const Duration(minutes: 15)));
    });
  });

  group('Android half', () {
    const dir = 'android/app/src/main/kotlin/com/wrfcoin/wrfcoin_mobile';
    final kotlin = File('$dir/CollectionWake.kt').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    test('channel, message and method names match on both sides', () {
      expect(kotlin, contains('"${CollectionWake.channelName}"'));
      expect(kotlin, contains('ALARM_MESSAGE = "$collectionAlarmMessage"'));
      for (final method in _FakeAndroid().methods) {
        expect(kotlin, contains('"$method" ->'));
      }
    });

    test('the application attaches it and the receiver is private', () {
      expect(manifest, contains('android:name=".WrfcoinApplication"'));
      expect(kotlin, contains('CollectionWake.install(this)'));
      expect(
        manifest,
        contains(
          RegExp(
            r'<receiver\s+android:name="\.CollectionAlarmReceiver"\s+'
            r'android:exported="false"/>',
          ),
        ),
      );
    });

    test('no exact-alarm or boot permission was added', () {
      expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(manifest, isNot(contains('USE_EXACT_ALARM')));
      expect(manifest, isNot(contains('RECEIVE_BOOT_COMPLETED')));
    });
  });
}

extension on _FakeAndroid {
  List<String> get methods => const [
    'beginTick',
    'endTick',
    'reschedule',
    'elapsedRealtime',
    'stop',
  ];
}
