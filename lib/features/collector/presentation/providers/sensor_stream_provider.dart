import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// A snapshot of live device sensor readings.
class SensorSnapshot {
  final double? temperature;
  final double? humidity;
  final double? pressure;
  final double accelerometerMagnitude;
  final int batteryLevel;
  final DateTime timestamp;

  const SensorSnapshot({
    this.temperature,
    this.humidity,
    this.pressure,
    required this.accelerometerMagnitude,
    required this.batteryLevel,
    required this.timestamp,
  });

  SensorSnapshot copyWith({
    double? temperature,
    double? humidity,
    double? pressure,
    double? accelerometerMagnitude,
    int? batteryLevel,
    DateTime? timestamp,
  }) {
    return SensorSnapshot(
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      pressure: pressure ?? this.pressure,
      accelerometerMagnitude:
          accelerometerMagnitude ?? this.accelerometerMagnitude,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Stream of live [SensorSnapshot] values from on-device sensors.
///
/// - Accelerometer magnitude is derived from [userAccelerometerEventStream].
/// - Battery level is polled every 30 seconds via [battery_plus].
/// - Temperature / humidity / pressure are device-hardware-dependent and may
///   be null on most phones (dedicated barometer / thermometer sensor absent).
///   Values are emitted as null when the hardware is unavailable.
final sensorStreamProvider = StreamProvider<SensorSnapshot>((ref) {
  return _SensorStreamController(ref).stream;
});

class _SensorStreamController {
  _SensorStreamController(Ref ref) {
    _controller = StreamController<SensorSnapshot>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }
  late final StreamController<SensorSnapshot> _controller;
  final Battery _battery = Battery();

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  Timer? _batteryTimer;

  SensorSnapshot _latest = SensorSnapshot(
    accelerometerMagnitude: 0,
    batteryLevel: -1,
    timestamp: DateTime.now(),
  );

  Stream<SensorSnapshot> get stream => _controller.stream;

  void _start() {
    if (!kIsWeb) {
      // Poll battery level immediately then every 30 s.
      _pollBattery();
      _batteryTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _pollBattery(),
      );

      // Listen to user-filtered accelerometer (removes gravity).
      _accelSub = userAccelerometerEventStream(
        samplingPeriod: SensorInterval.normalInterval,
      ).listen(_onAccelerometer, onError: (_) {});

      // Also subscribe barometer if available — update pressure field.
      _subscribeBarometer();
    } else {
      // Web: emit a static placeholder snapshot once.
      _controller.add(_latest);
    }
  }

  void _stop() {
    _accelSub?.cancel();
    _batteryTimer?.cancel();
    _controller.close();
  }

  Future<void> _pollBattery() async {
    try {
      final level = await _battery.batteryLevel;
      _latest = _latest.copyWith(
        batteryLevel: level,
        timestamp: DateTime.now(),
      );
      _emit();
    } catch (_) {
      // Battery unavailable — keep previous value.
    }
  }

  void _onAccelerometer(UserAccelerometerEvent event) {
    final mag = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    _latest = _latest.copyWith(
      accelerometerMagnitude: mag,
      timestamp: DateTime.now(),
    );
    _emit();
  }

  void _subscribeBarometer() {
    try {
      barometerEventStream().listen((event) {
        _latest = _latest.copyWith(
          pressure: event.pressure,
          timestamp: DateTime.now(),
        );
        _emit();
      }, onError: (_) {});
    } catch (_) {
      // Barometer sensor not available on this device — leave pressure as null.
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_latest);
    }
  }
}
