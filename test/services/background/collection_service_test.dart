// What one tick of the Collect service does and says.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/domain/collection_run.dart';
import 'package:wrfcoin_mobile/services/background/collection_service.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';

SyncRunResult _sync(SyncRunReason reason) => SyncRunResult(
  acceptedCount: reason == SyncRunReason.success ? 1 : 0,
  failedCount: 0,
  pendingCount: 0,
  reason: reason,
);

final _at = DateTime(2026, 11, 2, 15, 16);
final _time = DateFormat.jm().format(_at);
final _reading = CollectReadingResult.success(
  SensorReadingModel(
    latitude: 46.8,
    longitude: -92.1,
    pressureHpa: 1013,
    timestamp: _at,
  ),
);

void main() {
  group('runCollectionTick', () {
    test('turned off: stops, and takes no reading', () async {
      var collected = 0;
      final text = await runCollectionTick(
        stillWanted: () async => false,
        collect: () async {
          collected++;
          return _reading;
        },
        sync: () async => _sync(SyncRunReason.idle),
      );
      expect(text, isNull);
      expect(collected, 0);
    });

    test('a reading that uploads says so', () async {
      final text = await runCollectionTick(
        stillWanted: () async => true,
        collect: () async => _reading,
        sync: () async => _sync(SyncRunReason.success),
        now: () => _at,
      );
      expect(text, 'Last reading $_time, uploaded');
    });

    test('a failed upload does not stop the service or claim success', () async {
      final text = await runCollectionTick(
        stillWanted: () async => true,
        collect: () async => _reading,
        sync: () async => throw const CollectionRunFailed('offline'),
        now: () => _at,
      );
      expect(text, 'Last reading $_time, waiting to upload');
    });

    test('an empty run still uploads what is queued, and says why', () async {
      var synced = 0;
      final text = await runCollectionTick(
        stillWanted: () async => true,
        collect: () async => const CollectReadingResult.failure(
          CollectReadingFailureReason.barometerUnavailable,
        ),
        sync: () async {
          synced++;
          return _sync(SyncRunReason.success);
        },
        now: () => _at,
      );
      expect(synced, 1);
      expect(text, 'No reading at $_time: the barometer gave no data');
    });
  });

  group('collectionNotificationText names every empty run', () {
    for (final (reason, words) in [
      (CollectReadingFailureReason.batteryLow, 'battery is low'),
      (CollectReadingFailureReason.locationUnavailable, 'no location yet'),
      (CollectReadingFailureReason.locationTooOld, 'over a day old'),
      (CollectReadingFailureReason.stationaryBackoff, 'Running'),
    ]) {
      test(reason.name, () {
        final text = collectionNotificationText(
          CollectReadingResult.failure(reason),
          _at,
          upload: null,
        );
        expect(text, contains(words));
        expect(text, isNot(contains('Last reading')));
      });
    }
  });

  test('the manifest declares the location service and no background '
      'location', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION"')));
    expect(manifest, contains('FOREGROUND_SERVICE_LOCATION'));
    expect(
      manifest,
      contains(
        'com.pravera.flutter_foreground_task.service.ForegroundService',
      ),
    );
    expect(manifest, contains('android:foregroundServiceType="location"'));
  });
}
