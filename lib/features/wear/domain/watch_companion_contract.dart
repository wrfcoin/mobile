import 'package:flutter/foundation.dart' show immutable;

import '../../collector/data/models/sensor_reading_model.dart';

const Set<String> kWatchCompanionPlatforms = {
  'wearos',
  'watchos',
  'applewatch',
};

@immutable
class WatchCompanionContract {
  const WatchCompanionContract({
    required this.pressureHpa,
    required this.capturedAt,
    required this.platform,
    this.passiveCollectionEnabled,
    this.note,
  });

  factory WatchCompanionContract.fromReading(
    SensorReadingModel reading, {
    required String platform,
    bool? passiveCollectionEnabled,
    String? note,
  }) {
    return WatchCompanionContract(
      pressureHpa: reading.pressureHpa,
      capturedAt: reading.timestamp.toUtc(),
      platform: _normalizePlatform(platform),
      passiveCollectionEnabled: passiveCollectionEnabled,
      note: note,
    );
  }

  factory WatchCompanionContract.fromMap(Map<String, Object?> raw) {
    final rawPressure = raw['pressureHpa'];
    final pressure = rawPressure is num ? rawPressure.toDouble() : null;
    if (pressure == null || !pressure.isFinite) {
      throw const WatchCompanionPayloadFormatException(
        'pressureHpa must be a finite number',
      );
    }

    final rawCapturedAt = raw['capturedAt'];
    if (rawCapturedAt is! String || rawCapturedAt.trim().isEmpty) {
      throw const WatchCompanionPayloadFormatException(
        'capturedAt must be a non-empty ISO timestamp',
      );
    }
    final capturedAt = DateTime.tryParse(rawCapturedAt);
    if (capturedAt == null) {
      throw const WatchCompanionPayloadFormatException(
        'capturedAt must be ISO 8601',
      );
    }

    final rawPlatform = raw['platform'];
    if (rawPlatform is! String || rawPlatform.trim().isEmpty) {
      throw const WatchCompanionPayloadFormatException(
        'platform must be a non-empty string',
      );
    }
    final platform = _normalizePlatform(rawPlatform);

    final passiveCollectionEnabled = raw['passiveCollectionEnabled'] as bool?;

    final note = raw['note'];
    if (note != null && note is! String) {
      throw const WatchCompanionPayloadFormatException(
        'note must be a string when provided',
      );
    }

    return WatchCompanionContract(
      pressureHpa: pressure,
      capturedAt: capturedAt.toUtc(),
      platform: platform,
      passiveCollectionEnabled: passiveCollectionEnabled,
      // Safe: the guard above rejects any non-null note that is not a String.
      note: note as String?,
    );
  }

  static String _normalizePlatform(String platform) {
    final normalized = platform.toLowerCase().trim();
    if (!kWatchCompanionPlatforms.contains(normalized)) {
      throw const WatchCompanionPayloadFormatException(
        'platform must be one of wearos|watchos|applewatch',
      );
    }
    return normalized;
  }

  final double pressureHpa;
  final DateTime capturedAt;
  final String platform;
  final bool? passiveCollectionEnabled;
  final String? note;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'pressureHpa': pressureHpa,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'platform': platform,
      'passiveCollectionEnabled': passiveCollectionEnabled,
      'note': note,
    };
  }
}

class WatchCompanionPayloadFormatException implements Exception {
  const WatchCompanionPayloadFormatException(this.message);

  final String message;

  @override
  String toString() => 'WatchCompanionPayloadFormatException: $message';
}
