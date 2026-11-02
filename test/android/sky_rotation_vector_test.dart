// A Dart test cannot load the activity or a real sensor, so this pins the
// source of the Sky View channel and the no-camera decision. The behaviour on a
// real phone still needs a person with a phone.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_sensors.dart';

import 'dart:typed_data';

void main() {
  const dir = 'android/app/src/main/kotlin/com/wrfcoin/wrfcoin_mobile';
  final stream = File('$dir/SkyRotationVectorStream.kt').readAsStringSync();
  final activity = File('$dir/MainActivity.kt').readAsStringSync();

  test('uses the fused sensor and reads its accuracy status', () {
    expect(stream, contains('Sensor.TYPE_ROTATION_VECTOR'));
    expect(stream, contains('event.accuracy'));
    expect(stream, contains('onAccuracyChanged'));
    expect(stream, contains('event.values[4]'));
  });

  test('stops the sensor on cancel and when the engine goes away', () {
    expect(stream, contains('override fun onCancel'));
    expect(stream, contains('sensorManager.unregisterListener(this)'));
    expect(activity, contains('skyRotationVector?.stop()'));
  });

  test('channel name matches on both sides', () {
    expect(
      activity,
      contains('"com.wrfcoin.wrfcoin_mobile/sky_rotation_vector"'),
    );
    expect(
      SkySensors.rotationChannel.name,
      'com.wrfcoin.wrfcoin_mobile/sky_rotation_vector',
    );
  });

  test('decodes the channel format and refuses bad readings', () {
    final good = RotationVectorSample.decode(
      Float64List.fromList([1, 0, 0, 0, -1, 3, 1]),
    )!;
    expect(good.status, 3);
    expect(good.displayRotation, 1);
    expect(good.headingAccuracy, -1);
    for (final bad in <Object?>[
      null,
      'nope',
      Float64List.fromList([1, 0, 0]),
      Float64List.fromList([double.nan, 0, 0, 0, -1, 3, 0]),
      Float64List.fromList([0, 0, 0, 0, -1, 3, 0]),
    ]) {
      expect(RotationVectorSample.decode(bad), isNull);
    }
  });

  test('owner decision: no camera dependency, permission or code', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      RegExp(r'^\s*camera\w*:', multiLine: true).hasMatch(pubspec),
      isFalse,
    );
    expect(manifest, isNot(contains('android.permission.CAMERA')));
    final skySources = Directory('lib/features/sky_view')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in skySources) {
      expect(
        file.readAsStringSync(),
        isNot(contains('package:camera')),
        reason: file.path,
      );
    }
  });
}
