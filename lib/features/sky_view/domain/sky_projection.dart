import 'dart:math' as math;
import 'dart:ui';

import 'sky_attitude.dart';

/// Stereographic projection centred on the screen. It keeps constellations'
/// shapes at the edges better than a flat camera-style projection, and it turns
/// any circle on the sky into a circle on the screen, which the horizon uses.
class SkyProjection {
  final SkyPose pose;
  final Size size;
  final Offset center;

  /// Pixels per radian at the centre of the screen.
  final double scale;

  /// Degrees across the shorter side of the screen.
  static const shortSideFieldDegrees = 60.0;

  /// Nothing further than this from the screen centre is drawn.
  static const _minForward = -0.2;

  SkyProjection(this.pose, this.size)
    : center = size.center(Offset.zero),
      scale =
          size.shortestSide /
          (4 * math.tan(shortSideFieldDegrees * math.pi / 720));

  Offset? project(Vec3 direction) {
    final z = direction.dot(pose.forward);
    if (z < _minForward) return null;
    final k = 2 * scale / (1 + z);
    return Offset(
      center.dx + k * direction.dot(pose.right),
      center.dy - k * direction.dot(pose.up),
    );
  }

  /// The horizon as seen on screen, or a straight line when nearly level.
  HorizonShape get horizon {
    // The zenith in view coordinates. A direction d is on the horizon when
    // d . zenith = 0, which in the projection is a circle around
    // (ux, uy) / uz of radius 1 / |uz|, in units of 2 * scale.
    final ux = pose.right.z, uy = pose.up.z, uz = pose.forward.z;
    final unit = 2 * scale;
    final sideways = math.sqrt(ux * ux + uy * uy);
    if (uz.abs() < 0.005) {
      // Effectively a line, normal to the zenith's direction on screen. It sits
      // at the circle's nearest point so that nothing jumps at this threshold.
      final nx = ux / sideways, ny = -uy / sideways; // Screen y runs down.
      // (1 - sideways) / |uz|, written so it stays stable as uz approaches zero.
      final gap = unit * uz.abs() / (1 + sideways);
      final toLine = Offset(nx, ny) * (uz >= 0 ? -gap : gap);
      return HorizonShape.line(center + toLine, Offset(nx, ny));
    }
    return HorizonShape.circle(
      center + Offset(ux / uz, -uy / uz) * unit,
      unit / uz.abs(),
      groundOutside: uz > 0,
    );
  }
}

/// Either a circle or a straight line through [point] with [zenithward] as the
/// screen direction towards the sky.
class HorizonShape {
  final Offset point;
  final double? radius;
  final bool groundOutside;
  final Offset? zenithward;
  const HorizonShape.circle(
    this.point,
    double this.radius, {
    required this.groundOutside,
  }) : zenithward = null;
  const HorizonShape.line(this.point, Offset this.zenithward)
    : radius = null,
      groundOutside = false;
}
