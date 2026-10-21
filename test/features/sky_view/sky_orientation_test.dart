import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_orientation.dart';

void main() {
  test('rear normal points north, east and west in portrait', () {
    final north = skyOrientation([0, 9.8, 0], [0, -40, -30], 0)!;
    expect(north.azimuth, closeTo(0, 1e-6));
    expect(north.altitude, closeTo(0, 1e-6));
    // Facing the rear normal east puts geographic north to device-left (-x).
    final east = skyOrientation([0, 9.8, 0], [-30, -40, 0], 0)!;
    final west = skyOrientation([0, 9.8, 0], [30, -40, 0], 0)!;
    expect(east.azimuth, closeTo(90, 1e-6));
    expect(west.azimuth, closeTo(270, 1e-6));
  });
  test('camera normal elevation, including phone face-up and face-down', () {
    expect(
      skyOrientation([0, 0, 9.8], [0, 30, -40], 0)!.altitude,
      closeTo(-90, 1e-6),
    );
    expect(
      skyOrientation([0, 0, -9.8], [0, 30, 40], 0)!.altitude,
      closeTo(90, 1e-6),
    );
    expect(
      skyOrientation([0, 6.93, -6.93], [0, -49.5, 7.07], 0)!.altitude,
      closeTo(45, 0.01),
    );
  });
  test('east-positive declination corrects magnetic bearing with wrap', () {
    expect(
      skyOrientation([0, 9.8, 0], [0, -40, -30], 12)!.azimuth,
      closeTo(12, 1e-6),
    );
    expect(
      skyOrientation([0, 9.8, 0], [0, -40, -30], -12)!.azimuth,
      closeTo(348, 1e-6),
    );
  });
  test('missing/implausible/unusable vectors never fabricate orientation', () {
    for (final gravity in <List<double>>[
      [0.0, 0, 0],
      [0.0, 30, 0],
      [double.nan, 0, 0],
    ]) {
      expect(skyOrientation(gravity, [0, -40, -30], 0), isNull);
    }
    for (final magnetic in <List<double>>[
      [0.0, 0, 0],
      [0.0, 40, 0],
      [0.0, -999, 0],
    ]) {
      expect(skyOrientation([0, 9.8, 0], magnetic, 0), isNull);
    }
    expect(skyOrientation([0, 9.8, 0], [0, -40, -30], double.nan), isNull);
  });
}
