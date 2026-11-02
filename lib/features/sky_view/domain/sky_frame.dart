import '../../weather/domain/models/coarse_location.dart';
import 'sky_astronomy.dart';
import 'sky_attitude.dart';

/// The rotation from J2000 catalog directions to east, north, up for one
/// observer at one moment. Precession and the Earth's turning are both rigid
/// rotations, so three transformed axes describe every star: thousands of
/// stars cost one of these, not thousands of precessions.
class SkyFrame {
  /// Where the J2000 x (RA 0, Dec 0), y (RA 90, Dec 0) and z (north celestial
  /// pole) axes point, in east, north, up.
  final Vec3 xAxis, yAxis, zAxis;
  const SkyFrame._(this.xAxis, this.yAxis, this.zAxis);

  factory SkyFrame.at(DateTime utc, CoarseLocation cell) {
    Vec3 axis(double ra, double dec) {
      final at = toHorizontal(precess(Equatorial(ra, dec), utc), utc, cell);
      return Vec3.fromAzAlt(at.azimuth, at.altitude);
    }

    return SkyFrame._(axis(0, 0), axis(90, 0), axis(0, 90));
  }

  /// A catalog direction, in east, north, up.
  Vec3 toHorizontal3(double x, double y, double z) =>
      xAxis.scaled(x) + yAxis.scaled(y) + zAxis.scaled(z);

  /// An east, north, up direction, in the catalog's frame.
  Vec3 toCatalog(Vec3 direction) =>
      Vec3(direction.dot(xAxis), direction.dot(yAxis), direction.dot(zAxis));
}
