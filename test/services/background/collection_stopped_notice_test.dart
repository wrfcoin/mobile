// When the phone stops the collection service while Collect is on (night 4:
// Samsung Device Care restarted the system at 03:51), the WorkManager job
// tells the user once and skips the reading it cannot take.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/domain/collection_run.dart';
import 'package:wrfcoin_mobile/features/collector/domain/collection_status.dart';
import 'package:wrfcoin_mobile/services/background/collection_stopped_notice.dart';
import 'package:wrfcoin_mobile/services/background/sensor_worker.dart';

import '../../test_helpers/fakes.dart';

class _Notice {
  bool shown = false;
  int posted = 0;
  int cancelled = 0;

  Future<bool> check(bool? running) => checkCollectionServiceStopped(
    serviceRunning: () async => running,
    noticeShown: () async => shown,
    setNoticeShown: (value) async => shown = value,
    showNotice: () async => posted++,
    cancelNotice: () async => cancelled++,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('checkCollectionServiceStopped', () {
    test('service stopped: posts the notice and says stopped', () async {
      final notice = _Notice();
      expect(await notice.check(false), isTrue);
      expect(notice.posted, 1);
      expect(notice.shown, isTrue);
    });

    test(
      'stopped all night: the notice is posted once, not every job',
      () async {
        final notice = _Notice();
        for (var run = 0; run < 15; run++) {
          expect(await notice.check(false), isTrue);
        }
        expect(notice.posted, 1);
      },
    );

    test('service running: no notice, the job reads as before', () async {
      final notice = _Notice();
      expect(await notice.check(true), isFalse);
      expect(notice.posted, 0);
      expect(notice.cancelled, 0);
    });

    test('running again after a stop: removes the notice so the next stop '
        'posts it again', () async {
      final notice = _Notice();
      await notice.check(false);
      expect(await notice.check(true), isFalse);
      expect(notice.cancelled, 1);
      expect(notice.shown, isFalse);
      await notice.check(false);
      expect(notice.posted, 2);
    });

    test('unknown (no service on this platform, or the plugin cannot say): '
        'nothing changes', () async {
      final notice = _Notice();
      expect(await notice.check(null), isFalse);
      expect(notice.posted, 0);
    });
  });

  group('runSensorJobUnlessServiceStopped', () {
    test('service stopped: no reading attempt, a service_stopped run row, and '
        'WorkManager records a failure', () async {
      final store = FakeCollectorLocalStore();
      var read = 0;
      await expectLater(
        runSensorJobUnlessServiceStopped(
          serviceStopped: () async => true,
          store: store,
          job: () async => read++,
        ),
        throwsA(
          isA<CollectionRunFailed>().having(
            (e) => e.outcome,
            'outcome',
            CollectionOutcome.serviceStopped,
          ),
        ),
      );
      expect(read, 0);
      expect(store.recordedRuns, ['job:service_stopped']);
    });

    test('service running or unknown: the reading runs as before', () async {
      final store = FakeCollectorLocalStore();
      var read = 0;
      await runSensorJobUnlessServiceStopped(
        serviceStopped: () async => false,
        store: store,
        job: () async => read++,
      );
      expect(read, 1);
      expect(store.recordedRuns, isEmpty);
    });
  });

  test('the Collect card names the reason for a service_stopped run', () {
    expect(
      emptyRunReason(CollectionOutcome.serviceStopped),
      'the phone stopped collection in the background',
    );
  });

  test('the notice can be seen but does not ring every time', () {
    expect(
      collectionStoppedNoticeDetails.importance,
      Importance.defaultImportance,
    );
    expect(collectionStoppedNoticeDetails.onlyAlertOnce, isTrue);
    expect(collectionStoppedNoticeDetails.autoCancel, isTrue);
  });
}
