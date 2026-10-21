import 'dart:math' as math;

import '../models/sensor_reading_model.dart';

const double defaultMovementThresholdMeters = 50;

class SamplingDecision {
  final bool shouldCollect;
  final SamplingDecisionReason reason;
  final int intervalMinutes;
  final double? distanceMeters;
  final Duration? elapsedSinceLastReading;

  const SamplingDecision({
    required this.shouldCollect,
    required this.reason,
    required this.intervalMinutes,
    this.distanceMeters,
    this.elapsedSinceLastReading,
  });
}

enum SamplingDecisionReason {
  firstReading,
  moved,
  intervalElapsed,
  stationaryBackoff,
}

class BatteryImpactEstimate {
  final String label;
  final String detail;

  const BatteryImpactEstimate({required this.label, required this.detail});
}

class SamplingPolicy {
  const SamplingPolicy._();

  static int adaptiveIntervalMinutes({
    required int baseIntervalMinutes,
    required int batteryLevel,
  }) {
    if (batteryLevel < 20) {
      return (baseIntervalMinutes * 2).clamp(15, 60).toInt();
    }
    return baseIntervalMinutes.clamp(15, 60).toInt();
  }

  static SamplingDecision evaluate({
    required int baseIntervalMinutes,
    required int batteryLevel,
    required SensorReadingModel? previousReading,
    required double latitude,
    required double longitude,
    DateTime? now,
    double movementThresholdMeters = defaultMovementThresholdMeters,
  }) {
    final intervalMinutes = adaptiveIntervalMinutes(
      baseIntervalMinutes: baseIntervalMinutes,
      batteryLevel: batteryLevel,
    );

    if (previousReading == null) {
      return SamplingDecision(
        shouldCollect: true,
        reason: SamplingDecisionReason.firstReading,
        intervalMinutes: intervalMinutes,
      );
    }

    final elapsed = (now ?? DateTime.now()).difference(
      previousReading.timestamp,
    );
    if (elapsed >= Duration(minutes: intervalMinutes)) {
      return SamplingDecision(
        shouldCollect: true,
        reason: SamplingDecisionReason.intervalElapsed,
        intervalMinutes: intervalMinutes,
        elapsedSinceLastReading: elapsed,
      );
    }

    final distanceMeters = distanceBetweenMeters(
      previousReading.latitude,
      previousReading.longitude,
      latitude,
      longitude,
    );
    if (distanceMeters >= movementThresholdMeters) {
      return SamplingDecision(
        shouldCollect: true,
        reason: SamplingDecisionReason.moved,
        intervalMinutes: intervalMinutes,
        distanceMeters: distanceMeters,
        elapsedSinceLastReading: elapsed,
      );
    }

    return SamplingDecision(
      shouldCollect: false,
      reason: SamplingDecisionReason.stationaryBackoff,
      intervalMinutes: intervalMinutes,
      distanceMeters: distanceMeters,
      elapsedSinceLastReading: elapsed,
    );
  }

  static BatteryImpactEstimate estimateImpact({
    required int intervalMinutes,
    required int batteryThreshold,
  }) {
    final interval = intervalMinutes.clamp(15, 60).toInt();
    final samplesPerHour = 60 / interval;
    final label = interval >= 45
        ? 'Very low'
        : interval >= 30
        ? 'Low'
        : 'Balanced';

    return BatteryImpactEstimate(
      label: label,
      detail:
          '${samplesPerHour.toStringAsFixed(1)} samples/hour, pauses below '
          '$batteryThreshold%, and skips barometer reads while stationary.',
    );
  }

  static double distanceBetweenMeters(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadiusMeters = 6371000.0;
    final startLat = _degreesToRadians(startLatitude);
    final endLat = _degreesToRadians(endLatitude);
    final deltaLat = _degreesToRadians(endLatitude - startLatitude);
    final deltaLng = _degreesToRadians(endLongitude - startLongitude);

    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(startLat) *
            math.cos(endLat) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;
}
