import 'dart:math' as math;

import 'sky_astronomy.dart';

const _degree = math.pi / 180;

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -() => Vec3(-x, -y, -z);
  Vec3 scaled(double k) => Vec3(x * k, y * k, z * k);
  double get length => math.sqrt(dot(this));
  Vec3 get unit => scaled(1 / length);

  /// East, north, up unit vector for a true azimuth and altitude.
  factory Vec3.fromAzAlt(double azimuth, double altitude) {
    final a = azimuth * _degree, h = altitude * _degree;
    return Vec3(
      math.cos(h) * math.sin(a),
      math.cos(h) * math.cos(a),
      math.sin(h),
    );
  }
}

/// Unit quaternion taking device coordinates (x right, y top, z out of the
/// screen) to magnetic east, north, up. This is Android's TYPE_ROTATION_VECTOR
/// frame: its docs define world Y as pointing at the geomagnetic North Pole.
class Quat {
  final double w, x, y, z;
  const Quat(this.w, this.x, this.y, this.z);
  static const identity = Quat(1, 0, 0, 0);

  Quat get unit {
    final l = math.sqrt(w * w + x * x + y * y + z * z);
    return Quat(w / l, x / l, y / l, z / l);
  }

  /// Same formula as Android's SensorManager.getRotationMatrixFromVector.
  Vec3 rotate(Vec3 v) => Vec3(
    (1 - 2 * y * y - 2 * z * z) * v.x +
        (2 * x * y - 2 * z * w) * v.y +
        (2 * x * z + 2 * y * w) * v.z,
    (2 * x * y + 2 * z * w) * v.x +
        (1 - 2 * x * x - 2 * z * z) * v.y +
        (2 * y * z - 2 * x * w) * v.z,
    (2 * x * z - 2 * y * w) * v.x +
        (2 * y * z + 2 * x * w) * v.y +
        (1 - 2 * x * x - 2 * y * y) * v.z,
  );

  /// Builds from the world-frame images of the device x, y and z axes.
  factory Quat.fromAxes(Vec3 ax, Vec3 ay, Vec3 az) {
    final trace = ax.x + ay.y + az.z;
    if (trace > 0) {
      final s = 2 * math.sqrt(trace + 1);
      return Quat(
        s / 4,
        (ay.z - az.y) / s,
        (az.x - ax.z) / s,
        (ax.y - ay.x) / s,
      ).unit;
    }
    if (ax.x >= ay.y && ax.x >= az.z) {
      final s = 2 * math.sqrt(1 + ax.x - ay.y - az.z);
      return Quat(
        (ay.z - az.y) / s,
        s / 4,
        (ay.x + ax.y) / s,
        (az.x + ax.z) / s,
      ).unit;
    }
    if (ay.y >= az.z) {
      final s = 2 * math.sqrt(1 + ay.y - ax.x - az.z);
      return Quat(
        (az.x - ax.z) / s,
        (ay.x + ax.y) / s,
        s / 4,
        (az.y + ay.z) / s,
      ).unit;
    }
    final s = 2 * math.sqrt(1 + az.z - ax.x - ay.y);
    return Quat(
      (ax.y - ay.x) / s,
      (az.x + ax.z) / s,
      (az.y + ay.z) / s,
      s / 4,
    ).unit;
  }

  double _dot(Quat o) => w * o.w + x * o.x + y * o.y + z * o.z;

  /// Angle between two orientations, in degrees.
  double degreesTo(Quat o) =>
      2 * math.acos(_dot(o).abs().clamp(0.0, 1.0)) / _degree;

  /// Normalised lerp along the short way round (q and -q are the same pose).
  Quat towards(Quat o, double t) {
    final sign = _dot(o) < 0 ? -1.0 : 1.0;
    return Quat(
      w + (sign * o.w - w) * t,
      x + (sign * o.x - x) * t,
      y + (sign * o.y - y) * t,
      z + (sign * o.z - z) * t,
    ).unit;
  }
}

/// Tilt-compensated accelerometer/magnetometer fallback, in the same magnetic
/// frame as the rotation vector. Returns null for free fall, hard acceleration,
/// missing fields, nearby magnets, or vectors too parallel to give a heading.
Quat? magneticAttitudeFromVectors(List<double> gravity, List<double> magnetic) {
  if (gravity.length != 3 ||
      magnetic.length != 3 ||
      ![...gravity, ...magnetic].every((v) => v.isFinite)) {
    return null;
  }
  final g = Vec3(gravity[0], gravity[1], gravity[2]);
  final m = Vec3(magnetic[0], magnetic[1], magnetic[2]);
  if (g.length < 7 || g.length > 12 || m.length < 15 || m.length > 100) {
    return null;
  }
  final up = g.unit;
  final rawEast = m.cross(up);
  if (rawEast.length / m.length < 0.1) return null;
  final east = rawEast.unit;
  final north = up.cross(east);
  return Quat.fromAxes(
    Vec3(east.x, north.x, up.x),
    Vec3(east.y, north.y, up.y),
    Vec3(east.z, north.z, up.z),
  );
}

/// Android Display.getRotation() values, as a count of quarter turns. Returns
/// the device axes that point right and up on the screen as the user sees it.
/// ROTATION_90 means the phone was turned 90 degrees counter-clockwise, so its
/// x axis points up the screen and its top (y) points left; this matches
/// SensorManager.remapCoordinateSystem(AXIS_Y, AXIS_MINUS_X) in Android's docs.
(Vec3, Vec3) screenAxes(int displayRotation) => switch (displayRotation % 4) {
  1 => (const Vec3(0, -1, 0), const Vec3(1, 0, 0)),
  2 => (const Vec3(-1, 0, 0), const Vec3(0, -1, 0)),
  3 => (const Vec3(0, 1, 0), const Vec3(-1, 0, 0)),
  _ => (const Vec3(1, 0, 0), const Vec3(0, 1, 0)),
};

/// For the fallback path, where no platform reports the display rotation: when
/// the screen is landscape, gravity's sign along the device x axis picks the side.
int inferDisplayRotation({required bool landscape, required double gravityX}) =>
    !landscape ? 0 : (gravityX >= 0 ? 1 : 3);

/// Turns a vector about the local vertical so a magnetic azimuth A becomes A + D.
Vec3 _addAzimuth(Vec3 v, double degrees) {
  final c = math.cos(degrees * _degree), s = math.sin(degrees * _degree);
  return Vec3(v.x * c + v.y * s, v.y * c - v.x * s, v.z);
}

Vec3 _rotateAbout(Vec3 v, Vec3 axis, double degrees) {
  final c = math.cos(degrees * _degree), s = math.sin(degrees * _degree);
  return v.scaled(c) +
      axis.cross(v).scaled(s) +
      axis.scaled(axis.dot(v) * (1 - c));
}

/// The direction the phone faces, for azimuth purposes. When it points nearly
/// straight up, "forward" has almost no horizontal part and its azimuth would
/// spin on sensor noise, so this blends towards the direction opposite the
/// screen's up edge. That is the same bearing for an upright phone, and it stays
/// steady at the zenith.
Vec3 _stableHeading(Vec3 forward, Vec3 up) {
  const blendBelow = 0.2; // sin(11.5 degrees) from the vertical.
  final level = math.sqrt(forward.x * forward.x + forward.y * forward.y);
  final weight = math.max(0.0, 1 - level / blendBelow);
  final h = Vec3(forward.x - up.x * weight, forward.y - up.y * weight, 0);
  return h.length < 1e-9 ? const Vec3(0, 1, 0) : h.unit;
}

/// A small sky offset from "Align on a star", in degrees.
class SkyAlignment {
  final double azimuth, altitude;
  const SkyAlignment(this.azimuth, this.altitude);
  static const none = SkyAlignment(0, 0);
  bool get isSet => azimuth != 0 || altitude != 0;

  static const maxAzimuth = 30.0, maxAltitude = 15.0, maxTargetAltitude = 80.0;

  /// The offset that puts [target] at the boresight of an unaligned [pose].
  /// Null when the target is too high for azimuth to mean much, or when the
  /// gap is too big to be compass error, which means the wrong object or aim.
  static SkyAlignment? solve(SkyPose unaligned, Horizontal target) {
    if (target.altitude > maxTargetAltitude || target.altitude < 0) return null;
    final seen = unaligned.boresight;
    final az = (target.azimuth - seen.azimuth + 540) % 360 - 180;
    final alt = target.altitude - seen.altitude;
    if (az.abs() > maxAzimuth || alt.abs() > maxAltitude) return null;
    return SkyAlignment(az, alt);
  }
}

/// Where the screen is looking, in true-north east, north, up coordinates.
class SkyPose {
  final Vec3 right, up, forward;
  const SkyPose._(this.right, this.up, this.forward);

  /// The single place where magnetic becomes true. Both sensor paths hand in a
  /// magnetic-referenced [attitude]; neither applies declination itself.
  factory SkyPose.from(
    Quat attitude, {
    double declination = 0,
    SkyAlignment alignment = SkyAlignment.none,
    int displayRotation = 0,
  }) {
    final (deviceRight, deviceUp) = screenAxes(displayRotation);
    final turn = declination + alignment.azimuth;
    var right = _addAzimuth(attitude.rotate(deviceRight), turn);
    var up = _addAzimuth(attitude.rotate(deviceUp), turn);
    // The phone looks out of its back, so forward is device -z.
    var forward = _addAzimuth(attitude.rotate(const Vec3(0, 0, -1)), turn);
    if (alignment.altitude != 0) {
      final h = _stableHeading(forward, up);
      final axis = Vec3(
        h.y,
        -h.x,
        0,
      ); // Horizontal, to the right of the heading.
      right = _rotateAbout(right, axis, alignment.altitude);
      up = _rotateAbout(up, axis, alignment.altitude);
      forward = _rotateAbout(forward, axis, alignment.altitude);
    }
    return SkyPose._(right, up, forward);
  }

  /// True azimuth (north 0, east 90) and altitude of the screen centre.
  Horizontal get boresight {
    final h = _stableHeading(forward, up);
    return Horizontal(
      normalizeDegrees(math.atan2(h.x, h.y) / _degree),
      math.asin(forward.z.clamp(-1.0, 1.0)) / _degree,
    );
  }
}

/// Sensor smoothing: exponential follow on orientation, faster for big moves so
/// the map keeps up with the arm, with a dead band so a resting phone stops
/// drawing altogether.
class AttitudeSmoother {
  /// Time constant for small motion, in seconds.
  final double tau;
  AttitudeSmoother({required this.tau});

  /// A quarter of a pixel at phone width. Below this nothing is redrawn.
  static const deadBandDegrees = 0.05;
  static const _snapDegrees = 60.0;

  Quat? current;

  /// Moves towards [target]. Returns whether [current] changed.
  bool step(Quat target, double seconds) {
    final from = current;
    if (from == null) {
      current = target;
      return true;
    }
    final gap = from.degreesTo(target);
    if (gap < deadBandDegrees) return false;
    if (gap > _snapDegrees) {
      current = target;
      return true;
    }
    final quick = tau / (1 + gap / 5);
    current = from.towards(target, 1 - math.exp(-seconds / quick));
    return true;
  }
}
