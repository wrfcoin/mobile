import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_catalog.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_attitude.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_projection.dart';
import 'package:wrfcoin_mobile/features/sky_view/presentation/sky_map_painter.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';

Quat _upright(double azimuth, double altitude) {
  final h = (90 + altitude) * math.pi / 360, u = -azimuth * math.pi / 360;
  final x = Quat(math.cos(h), math.sin(h), 0, 0);
  final z = Quat(math.cos(u), 0, 0, math.sin(u));
  // Hamilton product z * x: tilt first, then turn about the vertical.
  return Quat(z.w * x.w, z.w * x.x, z.z * x.x, z.z * x.w);
}

void main() {
  const size = Size(390, 844);

  test('the boresight lands on the screen centre', () {
    final pose = SkyPose.from(_upright(120, 35));
    final at = SkyProjection(pose, size).project(pose.forward)!;
    expect(at.dx, closeTo(195, 1e-6));
    expect(at.dy, closeTo(422, 1e-6));
  });

  test('facing north: east is right and higher is up on the screen', () {
    final pose = SkyPose.from(_upright(0, 30));
    final projection = SkyProjection(pose, size);
    final center = projection.center;
    expect(
      projection.project(Vec3.fromAzAlt(10, 30))!.dx,
      greaterThan(center.dx),
    );
    expect(projection.project(Vec3.fromAzAlt(0, 40))!.dy, lessThan(center.dy));
  });

  test('the short side of the screen spans the stated field of view', () {
    final pose = SkyPose.from(_upright(0, 30));
    final edge = SkyProjection(
      pose,
      size,
    ).project(Vec3.fromAzAlt(0, 30 + SkyProjection.shortSideFieldDegrees / 2));
    // Half the short side (195 px) above the centre.
    expect(edge!.dy, closeTo(422 - 195, 1e-6));
  });

  test('what is behind the viewer is not drawn', () {
    final pose = SkyPose.from(_upright(0, 0));
    expect(SkyProjection(pose, size).project(Vec3.fromAzAlt(180, 0)), isNull);
  });

  group('horizon', () {
    /// Horizon points must lie on the shape; true for any pose.
    void check(SkyPose pose) {
      final projection = SkyProjection(pose, size);
      final shape = projection.horizon;
      for (var az = 0.0; az < 360; az += 5) {
        final at = projection.project(Vec3.fromAzAlt(az, 0));
        if (at == null || (at - projection.center).distance > 500) continue;
        final radius = shape.radius;
        if (radius != null) {
          expect((at - shape.point).distance, closeTo(radius, 1e-3));
        } else {
          final zenithward = shape.zenithward!;
          final off =
              (at - shape.point).dx * zenithward.dx +
              (at - shape.point).dy * zenithward.dy;
          expect(off.abs(), lessThan(1));
        }
      }
    }

    test('matches the projected horizon points in every pose', () {
      for (final alt in [-80.0, -30, -1.2, -0.5, 0, 0.5, 1.2, 30, 80, 89.9]) {
        for (final az in [0.0, 73, 200]) {
          check(SkyPose.from(_upright(az.toDouble(), alt.toDouble())));
        }
      }
    });

    test('nothing jumps as the phone tilts through level', () {
      Offset below(double alt) {
        final projection = SkyProjection(SkyPose.from(_upright(0, alt)), size);
        final shape = projection.horizon;
        final radius = shape.radius;
        if (radius == null) return shape.point;
        return shape.groundOutside
            ? shape.point + Offset(0, radius)
            : shape.point - Offset(0, radius);
      }

      var previous = below(-3);
      for (var alt = -3.0; alt <= 3; alt += 0.05) {
        final at = below(alt);
        expect((at - previous).distance, lessThan(1));
        previous = at;
      }
    });

    test('ground is on the correct side', () {
      // Looking up: the screen centre is sky, so ground is outside the circle.
      final up = SkyProjection(SkyPose.from(_upright(0, 40)), size).horizon;
      expect(up.groundOutside, isTrue);
      expect(
        (up.point - const Offset(195, 422)).distance,
        lessThan(up.radius!),
      );
      // Looking down: the centre is ground, inside the circle.
      final down = SkyProjection(SkyPose.from(_upright(0, -40)), size).horizon;
      expect(down.groundOutside, isFalse);
      expect(
        (down.point - const Offset(195, 422)).distance,
        lessThan(down.radius!),
      );
    });
  });

  group('tapping', () {
    final fixes = computeSky(
      DateTime.utc(2026, 11, 1, 6),
      CoarseLocation.round(37.8, -122.4),
    );

    test('finds the object under the finger', () {
      final target = fixes.firstWhere((f) => f.horizontal.altitude > 30);
      final pose = SkyPose.from(
        _upright(target.horizontal.azimuth, target.horizontal.altitude),
      );
      final hit = skyObjectAt(const Offset(195, 422), fixes, pose, size);
      expect(hit?.object.id, target.object.id);
    });

    test('an empty patch of sky returns nothing', () {
      final pose = SkyPose.from(_upright(0, 30));
      expect(skyObjectAt(const Offset(195, 422), const [], pose, size), isNull);
    });
  });

  test('stars are sized by magnitude, brighter is bigger', () {
    final fixes = computeSky(
      DateTime.utc(2026, 11, 1),
      CoarseLocation.round(0, 0),
    );
    final sirius = fixes.singleWhere((f) => f.object.name == 'Sirius');
    final polaris = fixes.singleWhere((f) => f.object.name == 'Polaris');
    expect(skyObjectRadius(sirius), greaterThan(skyObjectRadius(polaris)));
    for (final fix in fixes) {
      expect(skyObjectRadius(fix).isFinite, isTrue);
    }
  });
}
