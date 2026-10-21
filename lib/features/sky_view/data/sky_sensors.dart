import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

final skySensorsProvider = Provider<SkySensors>((ref) => SkySensors());
final skyClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

class SkySensors {
  Stream<List<double>> get gravity =>
      accelerometerEventStream(samplingPeriod: SensorInterval.normalInterval)
          .map((e) => [e.x, e.y, e.z]);
  Stream<List<double>> get magnetic =>
      magnetometerEventStream(samplingPeriod: SensorInterval.normalInterval)
          .map((e) => [e.x, e.y, e.z]);
}
