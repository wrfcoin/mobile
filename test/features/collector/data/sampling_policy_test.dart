import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/sampling_policy.dart';

void main() {
  group('SamplingPolicy', () {
    test('pauses barometer collection while stationary inside interval', () {
      final decision = SamplingPolicy.evaluate(
        baseIntervalMinutes: 15,
        batteryLevel: 80,
        previousReading: SensorReadingModel(
          latitude: 37.775,
          longitude: -122.419,
          pressureHpa: 1012,
          timestamp: DateTime(2026, 5, 29, 12),
        ),
        latitude: 37.7751,
        longitude: -122.4191,
        now: DateTime(2026, 5, 29, 12, 5),
      );

      expect(decision.shouldCollect, isFalse);
      expect(decision.reason, SamplingDecisionReason.stationaryBackoff);
      expect(decision.distanceMeters, lessThan(defaultMovementThresholdMeters));
    });

    test('collects when movement exceeds fifty meters', () {
      final decision = SamplingPolicy.evaluate(
        baseIntervalMinutes: 15,
        batteryLevel: 80,
        previousReading: SensorReadingModel(
          latitude: 37.775,
          longitude: -122.419,
          pressureHpa: 1012,
          timestamp: DateTime(2026, 5, 29, 12),
        ),
        latitude: 37.776,
        longitude: -122.419,
        now: DateTime(2026, 5, 29, 12, 5),
      );

      expect(decision.shouldCollect, isTrue);
      expect(decision.reason, SamplingDecisionReason.moved);
      expect(
        decision.distanceMeters,
        greaterThanOrEqualTo(defaultMovementThresholdMeters),
      );
    });

    test('backs off cadence when battery is low but above pause threshold', () {
      expect(
        SamplingPolicy.adaptiveIntervalMinutes(
          baseIntervalMinutes: 15,
          batteryLevel: 19,
        ),
        30,
      );
    });

    test('describes estimated impact for the dashboard', () {
      final estimate = SamplingPolicy.estimateImpact(
        intervalMinutes: 30,
        batteryThreshold: 15,
      );

      expect(estimate.label, 'Low');
      expect(estimate.detail, contains('2.0 samples/hour'));
      expect(estimate.detail, contains('pauses below 15%'));
    });
  });

  group('SamplingPolicy timer jitter', () {
    SensorReadingModel previous(DateTime at) => SensorReadingModel(
      latitude: 46.8,
      longitude: -92.1,
      pressureHpa: 1013,
      timestamp: at,
    );
    bool due(Duration elapsed) {
      final now = DateTime.utc(2026, 11, 2, 12);
      return SamplingPolicy.evaluate(
        baseIntervalMinutes: 15,
        batteryLevel: 80,
        previousReading: previous(now.subtract(elapsed)),
        latitude: 46.8,
        longitude: -92.1,
        now: now,
      ).shouldCollect;
    }

    test('a run a few seconds short counts as due', () {
      expect(due(const Duration(minutes: 14, seconds: 58)), isTrue);
    });

    test('a run clearly early does not', () {
      expect(due(const Duration(minutes: 13)), isFalse);
    });
  });
}
