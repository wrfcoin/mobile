// Background jobs re-check consent and the Collect switch before they read a
// sensor or upload: a job left behind after a withdrawal cancels itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collection_runner.dart';
import 'package:wrfcoin_mobile/services/background/sensor_worker.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('runIfCollectionAllowed', () {
    test(
      'not allowed: the job never runs and the jobs are cancelled',
      () async {
        var ran = 0;
        var cancelled = 0;
        await runIfCollectionAllowed(
          () async => ran++,
          allowed: () async => false,
          cancel: () async => cancelled++,
        );
        expect(ran, 0);
        expect(cancelled, 1);
      },
    );

    test('allowed: the job runs and nothing is cancelled', () async {
      var ran = 0;
      var cancelled = 0;
      await runIfCollectionAllowed(
        () async => ran++,
        allowed: () async => true,
        cancel: () async => cancelled++,
      );
      expect(ran, 1);
      expect(cancelled, 0);
    });
  });

  group('collectionStillAllowed', () {
    Future<bool> withPrefs(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return collectionStillAllowed();
    }

    const allOn = <String, Object>{
      'privacy.sensor_collection': true,
      'privacy.location_collection': true,
      'collector.isCollecting': true,
    };

    test('both consents and the switch on: allowed', () async {
      expect(await withPrefs(allOn), isTrue);
    });

    test('sensor consent withdrawn: not allowed', () async {
      expect(
        await withPrefs({...allOn, 'privacy.sensor_collection': false}),
        isFalse,
      );
    });

    test('location consent withdrawn: not allowed', () async {
      expect(
        await withPrefs({...allOn, 'privacy.location_collection': false}),
        isFalse,
      );
    });

    test('Collect switched off: not allowed', () async {
      expect(
        await withPrefs({...allOn, 'collector.isCollecting': false}),
        isFalse,
      );
    });

    test('a fresh install (nothing saved): not allowed', () async {
      expect(await withPrefs(const {}), isFalse);
    });
  });

  test('a run stopped because collection went off is not a failure', () {
    expect(syncRunSucceeded(SyncRunReason.collectionOff), isTrue);
  });
}
