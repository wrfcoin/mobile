import 'package:flutter/services.dart';

import '../../collector/data/models/sensor_reading_model.dart';

/// The minimal, privacy-preserving payload sent to a paired Wear OS companion.
/// It contains no wallet address or location; backend submission remains the
/// phone's responsibility.
class WearReadingPayload {
  const WearReadingPayload({
    required this.pressureHpa,
    required this.capturedAt,
  });

  factory WearReadingPayload.fromReading(SensorReadingModel reading) {
    return WearReadingPayload(
      pressureHpa: reading.pressureHpa,
      capturedAt: reading.timestamp.toUtc(),
    );
  }

  final double pressureHpa;
  final DateTime capturedAt;

  Map<String, Object> toMap() => {
    'pressureHpa': pressureHpa,
    'capturedAt': capturedAt.toIso8601String(),
  };
}

/// Android bridge for a paired Wear OS companion. A missing companion is a
/// normal no-op: the phone's collector and backend path remain authoritative.
class WearCompanionBridge {
  WearCompanionBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.wrfcoin.wrfcoin_mobile/wear_companion';
  final MethodChannel _channel;

  Future<int> publishReading(SensorReadingModel reading) async {
    final deliveredToNodes = await _channel.invokeMethod<int>(
      'publishReading',
      WearReadingPayload.fromReading(reading).toMap(),
    );
    return deliveredToNodes ?? 0;
  }
}
