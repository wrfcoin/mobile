import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../domain/sky_attitude.dart';

final skySensorsProvider = Provider<SkySensors>((ref) => SkySensors());
final skyClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// One TYPE_ROTATION_VECTOR reading from Android.
class RotationVectorSample {
  /// Device to magnetic east, north, up.
  final Quat attitude;

  /// SensorEvent.accuracy (SENSOR_STATUS_*).
  final int status;

  /// values[4]: estimated heading accuracy in radians, -1 when not available.
  final double headingAccuracy;

  /// Display.getRotation(), 0 to 3.
  final int displayRotation;

  const RotationVectorSample(
    this.attitude,
    this.status,
    this.headingAccuracy,
    this.displayRotation,
  );

  /// Decodes the channel's [w, x, y, z, heading, status, rotation] doubles.
  /// Null for anything that is not a usable reading.
  static RotationVectorSample? decode(Object? event) {
    if (event is! Float64List || event.length != 7) return null;
    if (!event.every((v) => v.isFinite)) return null;
    final attitude = Quat(event[0], event[1], event[2], event[3]);
    final size =
        attitude.w * attitude.w +
        attitude.x * attitude.x +
        attitude.y * attitude.y +
        attitude.z * attitude.z;
    if (size < 0.5 || size > 1.5) return null;
    return RotationVectorSample(
      attitude.unit,
      event[5].toInt(),
      event[4],
      event[6].toInt(),
    );
  }
}

class SkySensors {
  static const rotationChannel = EventChannel(
    'com.wrfcoin.wrfcoin_mobile/sky_rotation_vector',
  );

  /// Android's fused orientation. Errors when the phone has no such sensor or
  /// the platform has no such channel; the screen then uses the fallback.
  Stream<RotationVectorSample> get rotationVector {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Stream.error(
        PlatformException(code: 'unavailable', message: 'Android only'),
      );
    }
    return rotationChannel
        .receiveBroadcastStream()
        .map(RotationVectorSample.decode)
        .where((sample) => sample != null)
        .cast<RotationVectorSample>();
  }

  Stream<List<double>> get gravity =>
      accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .map((e) => [e.x, e.y, e.z]);
  Stream<List<double>> get magnetic =>
      magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .map((e) => [e.x, e.y, e.z]);
}
