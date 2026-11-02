import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_astronomy.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_attitude.dart';

Quat _aboutX(double degrees) {
  final h = degrees * math.pi / 360;
  return Quat(math.cos(h), math.sin(h), 0, 0);
}

Quat _aboutUp(double degrees) {
  final h = degrees * math.pi / 360;
  return Quat(math.cos(h), 0, 0, math.sin(h));
}

/// Hamilton product a * b: apply b first, then a.
Quat _then(Quat a, Quat b) => Quat(
  a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
  a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
  a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
  a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
);

/// Portrait, upright, back of the phone facing magnetic north, tilted up by
/// [altitude], then turned clockwise (seen from above) to magnetic [azimuth].
Quat _pointing(double azimuth, double altitude) =>
    _then(_aboutUp(-azimuth), _aboutX(90 + altitude));

void _closeVec(Vec3 actual, Vec3 expected, {double tolerance = 1e-9}) {
  expect(actual.x, closeTo(expected.x, tolerance));
  expect(actual.y, closeTo(expected.y, tolerance));
  expect(actual.z, closeTo(expected.z, tolerance));
}

double _azGap(double a, double b) => ((a - b + 540) % 360 - 180).abs();

void main() {
  group('known device poses', () {
    test('Android identity: flat, face up, top north, looks straight down', () {
      final pose = SkyPose.from(Quat.identity);
      _closeVec(pose.right, const Vec3(1, 0, 0));
      _closeVec(pose.up, const Vec3(0, 1, 0));
      _closeVec(pose.forward, const Vec3(0, 0, -1));
      expect(pose.boresight.altitude, closeTo(-90, 1e-6));
    });

    test('upright portrait, back facing north', () {
      final pose = SkyPose.from(_aboutX(90));
      _closeVec(pose.forward, const Vec3(0, 1, 0));
      _closeVec(pose.up, const Vec3(0, 0, 1));
      _closeVec(pose.right, const Vec3(1, 0, 0));
      expect(pose.boresight.altitude, closeTo(0, 1e-9));
      expect(pose.boresight.azimuth % 360, closeTo(0, 1e-9));
    });

    test('every compass bearing and altitude reads back', () {
      for (final az in [0.0, 45, 90, 135, 180, 225, 270, 315]) {
        for (final alt in [-60.0, 0, 30, 60, 75]) {
          final at = SkyPose.from(_pointing(az.toDouble(), alt.toDouble()))
              .boresight;
          expect(_azGap(at.azimuth, az.toDouble()), lessThan(1e-6));
          expect(at.altitude, closeTo(alt, 1e-6));
        }
      }
    });

    test('quaternion rotation agrees with the axes it was built from', () {
      final q = _then(_aboutUp(-37), _aboutX(61));
      final rebuilt = Quat.fromAxes(
        q.rotate(const Vec3(1, 0, 0)),
        q.rotate(const Vec3(0, 1, 0)),
        q.rotate(const Vec3(0, 0, 1)),
      );
      expect(rebuilt.degreesTo(q), lessThan(1e-3));
      // Each branch of the conversion, including the 180 degree turns.
      for (final q in [_aboutX(180), _aboutUp(180), const Quat(0, 0, 1, 0)]) {
        final again = Quat.fromAxes(
          q.rotate(const Vec3(1, 0, 0)),
          q.rotate(const Vec3(0, 1, 0)),
          q.rotate(const Vec3(0, 0, 1)),
        );
        expect(again.degreesTo(q), lessThan(1e-3));
      }
    });
  });

  group('portrait and landscape', () {
    // Facing north. Display rotation describes how the phone is held, and the
    // pointing direction must not change, but screen right must stay east and
    // screen up must stay up, or the map would be drawn sideways.
    test('ROTATION_90: turned counter-clockwise, top points west', () {
      // Device x is up, y is west, z is south.
      final attitude = Quat.fromAxes(
        const Vec3(0, 0, 1),
        const Vec3(-1, 0, 0),
        const Vec3(0, -1, 0),
      );
      final pose = SkyPose.from(attitude, displayRotation: 1);
      _closeVec(pose.forward, const Vec3(0, 1, 0));
      _closeVec(pose.right, const Vec3(1, 0, 0));
      _closeVec(pose.up, const Vec3(0, 0, 1));
    });

    test('ROTATION_270: turned clockwise, top points east', () {
      // Device x is down, y is east, z is south.
      final attitude = Quat.fromAxes(
        const Vec3(0, 0, -1),
        const Vec3(1, 0, 0),
        const Vec3(0, -1, 0),
      );
      final pose = SkyPose.from(attitude, displayRotation: 3);
      _closeVec(pose.forward, const Vec3(0, 1, 0));
      _closeVec(pose.right, const Vec3(1, 0, 0));
      _closeVec(pose.up, const Vec3(0, 0, 1));
    });

    test('ROTATION_180: upside down', () {
      // Device x is west, y is down, z is south.
      final attitude = Quat.fromAxes(
        const Vec3(-1, 0, 0),
        const Vec3(0, 0, -1),
        const Vec3(0, -1, 0),
      );
      final pose = SkyPose.from(attitude, displayRotation: 2);
      _closeVec(pose.forward, const Vec3(0, 1, 0));
      _closeVec(pose.right, const Vec3(1, 0, 0));
      _closeVec(pose.up, const Vec3(0, 0, 1));
    });

    test('screen axes stay a right-handed frame in all four rotations', () {
      final attitude = _pointing(123, 34);
      for (var rotation = 0; rotation < 4; rotation++) {
        final pose = SkyPose.from(attitude, displayRotation: rotation);
        // Right cross up points out of the screen, towards the viewer.
        _closeVec(pose.right.cross(pose.up), -pose.forward, tolerance: 1e-9);
      }
    });

    test(
      'fallback without a platform rotation picks the side from gravity',
      () {
        expect(inferDisplayRotation(landscape: false, gravityX: 9), 0);
        expect(inferDisplayRotation(landscape: true, gravityX: 9), 1);
        expect(inferDisplayRotation(landscape: true, gravityX: -9), 3);
      },
    );
  });

  group('declination is applied exactly once', () {
    const d = 13.5;
    // Android documents TYPE_ROTATION_VECTOR's world Y as geomagnetic north.
    test('rotation vector: magnetic north reads true azimuth D', () {
      final at = SkyPose.from(_pointing(0, 20), declination: d).boresight;
      expect(at.azimuth, closeTo(d, 1e-9));
      expect(_azGap(at.azimuth, 2 * d), greaterThan(d - 1e-9));
    });

    test('both sensor paths agree for the same real pose', () {
      // Back of the phone at magnetic north, upright. A field pointing north
      // and down: seen in device axes, north is -z and down is -y.
      final fallback = magneticAttitudeFromVectors([0, 9.8, 0], [0, -40, -30])!;
      final a = SkyPose.from(fallback, declination: d).boresight;
      final b = SkyPose.from(_pointing(0, 0), declination: d).boresight;
      expect(a.azimuth, closeTo(d, 1e-9));
      expect(b.azimuth, closeTo(d, 1e-9));
    });

    test(
      'west declination wraps, and true minus magnetic is D at any bearing',
      () {
        for (final az in [0.0, 90, 200, 359]) {
          for (final dec in [-20.0, -0.5, 0, 7, 30]) {
            final magnetic = SkyPose.from(_pointing(az.toDouble(), 10))
                .boresight;
            final truth = SkyPose.from(
              _pointing(az.toDouble(), 10),
              declination: dec.toDouble(),
            ).boresight;
            expect(
              ((truth.azimuth - magnetic.azimuth - dec + 540) % 360) - 180,
              closeTo(0, 1e-9),
            );
          }
        }
      },
    );

    test('declination never changes altitude', () {
      expect(
        SkyPose.from(_pointing(40, 25), declination: 25).boresight.altitude,
        closeTo(25, 1e-9),
      );
    });
  });

  group('pointing straight up', () {
    test('exact zenith gives a finite reading, not a crash', () {
      final at = SkyPose.from(_aboutX(180)).boresight;
      expect(at.altitude, closeTo(90, 1e-4));
      expect(at.azimuth.isFinite, isTrue);
    });

    test('noise around the zenith does not swing the azimuth', () {
      final random = math.Random(7);
      final readings = <double>[];
      for (var i = 0; i < 2000; i++) {
        // Half a degree of tilt noise in both directions around straight up.
        final tiltX = 180 + (random.nextDouble() - 0.5);
        final tiltY = (random.nextDouble() - 0.5);
        final h = tiltY * math.pi / 360;
        final q = _then(Quat(math.cos(h), 0, math.sin(h), 0), _aboutX(tiltX));
        readings.add(SkyPose.from(q).boresight.azimuth);
      }
      for (final reading in readings) {
        expect(reading.isFinite, isTrue);
        expect(_azGap(reading, readings.first), lessThan(5));
      }
    });

    test('tilting up to it stays continuous and keeps the bearing', () {
      for (final bearing in [0.0, 77, 200]) {
        var previous = SkyPose.from(_pointing(bearing.toDouble(), 0)).boresight;
        for (var alt = 1.0; alt <= 90; alt += 1) {
          final at = SkyPose.from(_pointing(bearing.toDouble(), alt)).boresight;
          expect(_azGap(at.azimuth, previous.azimuth), lessThan(0.5));
          expect(_azGap(at.azimuth, bearing.toDouble()), lessThan(1e-6));
          previous = at;
        }
      }
    });

    test('straight up and rolled, the map axes stay valid', () {
      for (var roll = 0.0; roll < 360; roll += 15) {
        final pose = SkyPose.from(_then(_aboutUp(roll), _aboutX(180)));
        expect(pose.boresight.altitude, closeTo(90, 1e-4));
        expect(pose.boresight.azimuth.isFinite, isTrue);
        expect(pose.right.length, closeTo(1, 1e-9));
        expect(pose.up.length, closeTo(1, 1e-9));
      }
    });
  });

  group('align on a star', () {
    test('moves the boresight onto the target', () {
      final attitude = _pointing(100, 40);
      final unaligned = SkyPose.from(attitude);
      const target = Horizontal(106, 41.5);
      final offset = SkyAlignment.solve(unaligned, target)!;
      expect(offset.azimuth, closeTo(6, 1e-6));
      expect(offset.altitude, closeTo(1.5, 1e-6));
      final aligned = SkyPose.from(attitude, alignment: offset).boresight;
      expect(aligned.azimuth, closeTo(106, 1e-6));
      expect(aligned.altitude, closeTo(41.5, 1e-6));
    });

    test('wraps across north', () {
      final offset = SkyAlignment.solve(
        SkyPose.from(_pointing(358, 30)),
        const Horizontal(3, 30),
      )!;
      expect(offset.azimuth, closeTo(5, 1e-6));
    });

    test('is added on top of declination, not instead of it', () {
      final pose = SkyPose.from(
        _pointing(0, 20),
        declination: 10,
        alignment: const SkyAlignment(2, 0),
      );
      expect(pose.boresight.azimuth, closeTo(12, 1e-9));
    });

    test('keeps the frame orthonormal', () {
      final pose = SkyPose.from(
        _pointing(70, 30),
        alignment: const SkyAlignment(-4, 3),
      );
      expect(pose.right.dot(pose.up), closeTo(0, 1e-9));
      expect(pose.right.dot(pose.forward), closeTo(0, 1e-9));
      expect(pose.up.dot(pose.forward), closeTo(0, 1e-9));
    });

    test('refuses a big gap, a very high target and one below the horizon', () {
      final pose = SkyPose.from(_pointing(100, 40));
      expect(SkyAlignment.solve(pose, const Horizontal(170, 40)), isNull);
      expect(SkyAlignment.solve(pose, const Horizontal(100, 70)), isNull);
      expect(
        SkyAlignment.solve(
          SkyPose.from(_pointing(100, 78)),
          const Horizontal(100, 85),
        ),
        isNull,
      );
      expect(
        SkyAlignment.solve(
          SkyPose.from(_pointing(100, 3)),
          const Horizontal(100, -2),
        ),
        isNull,
      );
    });
  });

  group('smoothing', () {
    double spread(List<double> values) {
      final mean = values.reduce((a, b) => a + b) / values.length;
      return math.sqrt(
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length,
      );
    }

    test('reduces sensor noise', () {
      final random = math.Random(3);
      final raw = <double>[], smooth = <double>[];
      final smoother = AttitudeSmoother(tau: 0.35);
      for (var i = 0; i < 600; i++) {
        final noisy = _pointing(100 + (random.nextDouble() - 0.5) * 2, 30);
        smoother.step(noisy, 1 / 30);
        if (i > 60) {
          raw.add(SkyPose.from(noisy).boresight.azimuth);
          smooth.add(SkyPose.from(smoother.current!).boresight.azimuth);
        }
      }
      expect(spread(smooth), lessThan(spread(raw) / 2));
    });

    test('catches up with a real move without overshoot', () {
      final smoother = AttitudeSmoother(tau: 0.08);
      smoother.step(_pointing(100, 30), 1 / 30);
      final target = _pointing(130, 30);
      var last = 100.0;
      for (var i = 0; i < 60; i++) {
        smoother.step(target, 1 / 30);
        final az = SkyPose.from(smoother.current!).boresight.azimuth;
        expect(az, greaterThanOrEqualTo(last - 1e-6));
        expect(az, lessThanOrEqualTo(130 + 1e-6));
        last = az;
      }
      expect(last, closeTo(130, 0.1));
    });

    test('takes the short way when the sensor flips the quaternion sign', () {
      final q = _pointing(10, 20);
      final negated = Quat(-q.w, -q.x, -q.y, -q.z);
      final smoother = AttitudeSmoother(tau: 0.1)..current = q;
      expect(smoother.step(negated, 1 / 30), isFalse);
      expect(q.towards(negated, 0.5).degreesTo(q), lessThan(1e-6));
    });

    test('a resting phone stops asking for frames', () {
      final smoother = AttitudeSmoother(tau: 0.1);
      expect(smoother.step(_pointing(50, 20), 1 / 30), isTrue);
      expect(smoother.step(_pointing(50.01, 20), 1 / 30), isFalse);
    });
  });
}
