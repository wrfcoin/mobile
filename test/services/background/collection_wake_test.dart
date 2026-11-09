// When the Collect service ticks, and how long it keeps the CPU awake for it.
// A Dart test cannot run the alarm or the lock, so the Android half is pinned
// by its source. The battery saving itself still needs a night on a phone.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/background/collection_service.dart';
import 'package:wrfcoin_mobile/services/background/collection_wake.dart';

const _interval = Duration(minutes: 15);
const _hold = Duration(minutes: 11);
final _last = DateTime(2026, 11, 9, 23, 0);

bool _due(
  CollectionTickTrigger trigger,
  Duration sinceLast, {
  bool alarmDriven = true,
}) => collectionTickDue(
  trigger: trigger,
  now: _last.add(sinceLast),
  lastTickStartedAt: _last,
  interval: _interval,
  alarmDriven: alarmDriven,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('collectionTickDue', () {
    test('the first tick and a service start always run', () {
      for (final trigger in CollectionTickTrigger.values) {
        expect(
          collectionTickDue(
            trigger: trigger,
            now: _last,
            lastTickStartedAt: null,
            interval: _interval,
            alarmDriven: true,
          ),
          isTrue,
        );
      }
      expect(_due(CollectionTickTrigger.start, Duration.zero), isTrue);
    });

    test('the alarm runs a tick one interval after the last', () {
      expect(_due(CollectionTickTrigger.alarm, _interval), isTrue);
      // A little early still counts: exact alarms are not to the millisecond.
      expect(
        _due(CollectionTickTrigger.alarm, const Duration(minutes: 14)),
        isTrue,
      );
    });

    test('an alarm left over from before a restart is dropped', () {
      expect(
        _due(CollectionTickTrigger.alarm, const Duration(minutes: 1)),
        isFalse,
      );
    });

    test('with the alarm working, the repeat timer only covers a late one', () {
      expect(
        _due(CollectionTickTrigger.timer, const Duration(minutes: 7)),
        isFalse,
      );
      expect(_due(CollectionTickTrigger.timer, _interval), isFalse);
      expect(
        _due(CollectionTickTrigger.timer, const Duration(minutes: 17)),
        isTrue,
      );
    });

    test('a late alarm is covered before a 20 minute gap', () {
      expect(
        _interval + collectionAlarmLateGrace,
        lessThan(const Duration(minutes: 20)),
      );
    });

    test('with no alarm, every repeat timer tick runs, as before', () {
      expect(
        _due(CollectionTickTrigger.timer, _interval, alarmDriven: false),
        isTrue,
      );
    });

    test('a clock set back does not stop the ticks', () {
      expect(
        _due(CollectionTickTrigger.timer, const Duration(hours: -3)),
        isTrue,
      );
    });
  });

  group('collectionNextAlarmDelay', () {
    Duration delay(Duration sinceLast, Duration interval) =>
        collectionNextAlarmDelay(
          now: _last.add(sinceLast),
          lastTickStartedAt: _last,
          interval: interval,
        );

    test('counts the new interval from the last tick', () {
      expect(
        delay(const Duration(minutes: 5), const Duration(minutes: 30)),
        const Duration(minutes: 25),
      );
    });

    test('is now when the new interval has already passed', () {
      expect(
        delay(const Duration(minutes: 40), const Duration(minutes: 15)),
        Duration.zero,
      );
    });

    test('is one interval with no tick yet', () {
      expect(
        collectionNextAlarmDelay(
          now: _last,
          lastTickStartedAt: null,
          interval: _interval,
        ),
        _interval,
      );
    });
  });

  group('CollectionWake', () {
    const channel = MethodChannel(CollectionWake.channelName);
    final calls = <String>[];
    bool? alarmAnswer;

    String describe(MethodCall call) {
      final arguments = call.arguments as Map<Object?, Object?>?;
      return switch (call.method) {
        'acquire' => 'acquire ${arguments?['timeoutMs']}',
        'scheduleAlarm' =>
          'scheduleAlarm ${arguments?['delayMs']} ${arguments?['holdMs']}',
        _ => call.method,
      };
    }

    setUp(() {
      calls.clear();
      alarmAnswer = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(describe(call));
            return call.method == 'scheduleAlarm' ? alarmAnswer : null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'a tick takes a timed lock, sets the next alarm, then lets go',
      () async {
        final wake = CollectionWake();
        expect(await wake.beginTick(interval: _interval, hold: _hold), isTrue);
        await wake.endTick();
        expect(calls, [
          'acquire ${_hold.inMilliseconds}',
          'scheduleAlarm ${_interval.inMilliseconds} ${_hold.inMilliseconds}',
          'release',
        ]);
      },
    );

    test('no exact alarm: the lock is held between ticks, as before', () async {
      alarmAnswer = false;
      final wake = CollectionWake();
      expect(await wake.beginTick(interval: _interval, hold: _hold), isFalse);
      await wake.endTick();
      expect(calls, [
        'acquire ${_hold.inMilliseconds}',
        'scheduleAlarm ${_interval.inMilliseconds} ${_hold.inMilliseconds}',
        'acquire null',
      ]);
      expect(calls, isNot(contains('release')));
    });

    test(
      'once an alarm can be set again, the held lock is given back',
      () async {
        alarmAnswer = false;
        final wake = CollectionWake();
        await wake.beginTick(interval: _interval, hold: _hold);
        await wake.endTick();
        alarmAnswer = true;
        calls.clear();
        await wake.beginTick(interval: _interval, hold: _hold);
        await wake.endTick();
        expect(calls.last, 'release');
      },
    );

    test('a dropped alarm gives its lock back', () async {
      final wake = CollectionWake();
      await wake.beginTick(interval: _interval, hold: _hold);
      await wake.endTick();
      calls.clear();
      await wake.dropTick();
      expect(calls, ['release']);
    });

    test('a dropped alarm never puts a time limit on a held lock', () async {
      alarmAnswer = false;
      final wake = CollectionWake();
      await wake.beginTick(interval: _interval, hold: _hold);
      calls.clear();
      await wake.dropTick();
      expect(calls, ['acquire null']);
    });

    test('the alarm is only moved when it drives the ticks', () async {
      final wake = CollectionWake();
      await wake.reschedule(delay: const Duration(minutes: 3), hold: _hold);
      expect(calls, isEmpty);
      await wake.beginTick(interval: _interval, hold: _hold);
      calls.clear();
      await wake.reschedule(delay: const Duration(minutes: 3), hold: _hold);
      expect(calls, ['scheduleAlarm 180000 ${_hold.inMilliseconds}']);
    });

    test('stopping cancels the alarm and gives the lock back', () async {
      final wake = CollectionWake();
      await wake.beginTick(interval: _interval, hold: _hold);
      calls.clear();
      await wake.stop();
      expect(calls, ['cancelAlarm', 'release']);
      expect(wake.alarmDriven, isFalse);
    });

    test('without the Android half nothing throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final wake = CollectionWake();
      expect(await wake.beginTick(interval: _interval, hold: _hold), isFalse);
      await wake.endTick();
      await wake.dropTick();
      await wake.stop();
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

    test('channel and message names match on both sides', () {
      expect(kotlin, contains('"${CollectionWake.channelName}"'));
      expect(kotlin, contains('ALARM_MESSAGE = "$collectionAlarmMessage"'));
    });

    test('the alarm is exact, fires in doze, and asks before it is set', () {
      expect(kotlin, contains('setExactAndAllowWhileIdle'));
      expect(kotlin, contains('ELAPSED_REALTIME_WAKEUP'));
      expect(kotlin, contains('canScheduleExactAlarms()'));
      expect(kotlin, contains('catch (e: SecurityException)'));
    });

    test('the tick lock is timed and the service leaves nothing behind', () {
      expect(kotlin, contains('lock.acquire(timeoutMs)'));
      expect(kotlin, contains('setReferenceCounted(false)'));
      final teardown = kotlin.substring(
        kotlin.indexOf('override fun onEngineWillDestroy'),
        kotlin.indexOf('private fun onMethodCall'),
      );
      expect(teardown, contains('cancelAlarm()'));
      expect(teardown, contains('release()'));
    });

    test('a stopped service gets no lock from a late alarm', () {
      final onAlarm = kotlin.substring(kotlin.indexOf('fun onAlarm'));
      expect(
        onAlarm.indexOf('isRunningServiceState.value) return'),
        lessThan(onAlarm.indexOf('acquire(holdMs)')),
      );
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
