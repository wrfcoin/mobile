import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/wear/domain/watch_companion_summary.dart';

void main() {
  test('builds a glance summary from readings in a lookback window', () {
    final now = DateTime.utc(2026, 7, 30, 12);
    final readings = <SensorReadingModel>[
      SensorReadingModel(
        latitude: 0,
        longitude: 0,
        pressureHpa: 1012.1,
        timestamp: DateTime.utc(2026, 7, 30, 11, 0),
        synced: false,
      ),
      SensorReadingModel(
        latitude: 0,
        longitude: 0,
        pressureHpa: 1013.5,
        timestamp: now,
        synced: true,
      ),
      SensorReadingModel(
        latitude: 0,
        longitude: 0,
        pressureHpa: 1000,
        timestamp: DateTime.utc(2026, 7, 30, 8, 0),
        synced: true,
      ),
    ];

    final summary = WatchCompanionSummary.fromReadings(
      readings: readings,
      window: const Duration(hours: 2),
      passiveCollectionEnabled: true,
      now: now,
    );

    expect(summary.readingsInWindow, 2);
    expect(summary.lastPressureHpa, equals(1013.5));
    expect(summary.passiveCollectionEnabled, isTrue);
    expect(summary.summarize(), contains('1013.5 hPa'));
  });
}
