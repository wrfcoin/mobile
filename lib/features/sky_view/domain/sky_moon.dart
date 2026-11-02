import 'dart:math' as math;

import '../../weather/domain/models/coarse_location.dart';
import 'sky_astronomy.dart';

const _degree = math.pi / 180;
double _sin(double d) => math.sin(d * _degree);
double _cos(double d) => math.cos(d * _degree);

/// Precession of the equinoxes in ecliptic longitude, degrees per Julian
/// century (Meeus, Astronomical Algorithms, chapter 21: 5029.0966 arcsec).
const _generalPrecession = 5029.0966 / 3600;
const _obliquityJ2000 = 23.43928; // Same value solarSystem() uses.

class MoonPosition {
  /// Geocentric J2000 position, in the same frame as every other SkyObject.
  final Equatorial position;

  /// Equatorial horizontal parallax, degrees (about 0.9 to 1.0).
  final double horizontalParallax;
  const MoonPosition(this.position, this.horizontalParallax);
}

/// Low-precision lunar position from The Astronomical Almanac, Section D, "Low
/// precision formulae for the Moon's position" (Earth-Moon mean elements with
/// the largest periodic terms). The Almanac states about 0.3 degrees in
/// longitude and 0.2 degrees in latitude for 1900 to 2100.
///
/// The formula returns longitude of date. Subtracting general precession moves
/// it to J2000 so the shared precess() pipeline applies. The small change in the
/// ecliptic's own tilt is ignored. No light-time, aberration or nutation.
MoonPosition moonPosition(DateTime utc) {
  final year = utc.toUtc().year;
  if (year < 1800 || year > 2050) {
    throw RangeError('Ephemeris supports 1800–2050');
  }
  final t = (julianDay(utc) - 2451545) / 36525;
  final longitudeOfDate =
      218.32 +
      481267.881 * t +
      6.29 * _sin(135.0 + 477198.87 * t) -
      1.27 * _sin(259.3 - 413335.36 * t) +
      0.66 * _sin(235.7 + 890534.22 * t) +
      0.21 * _sin(269.9 + 954397.74 * t) -
      0.19 * _sin(357.5 + 35999.05 * t) -
      0.11 * _sin(186.5 + 966404.03 * t);
  final latitude =
      5.13 * _sin(93.3 + 483202.02 * t) +
      0.28 * _sin(228.2 + 960400.89 * t) -
      0.28 * _sin(318.3 + 6003.15 * t) -
      0.17 * _sin(217.6 - 407332.21 * t);
  final parallax =
      0.9508 +
      0.0518 * _cos(135.0 + 477198.87 * t) +
      0.0095 * _cos(259.3 - 413335.36 * t) +
      0.0078 * _cos(235.7 + 890534.22 * t) +
      0.0028 * _cos(269.9 + 954397.74 * t);
  final longitude = longitudeOfDate - _generalPrecession * t;
  final x = _cos(latitude) * _cos(longitude);
  final y =
      _cos(_obliquityJ2000) * _cos(latitude) * _sin(longitude) -
      _sin(_obliquityJ2000) * _sin(latitude);
  final z =
      _sin(_obliquityJ2000) * _cos(latitude) * _sin(longitude) +
      _cos(_obliquityJ2000) * _sin(latitude);
  return MoonPosition(
    Equatorial(
      normalizeDegrees(math.atan2(y, x) / _degree),
      math.asin(z.clamp(-1.0, 1.0)) / _degree,
    ),
    parallax,
  );
}

const moonId = 'Moon';

SkyObject moonObject(DateTime utc) =>
    SkyObject(moonId, moonId, '', moonPosition(utc).position, double.nan);

/// Where [object] sits for someone standing at [cell], in the mean frame of the
/// date. Only the Moon is close enough to shift: it sits up to about a degree
/// lower than its geocentric position, by altitude minus parallax times
/// cos(altitude). Azimuth is unchanged by this approximation, which assumes a
/// spherical Earth. Still geometric: no refraction.
Horizontal observedHorizontal(
  SkyObject object,
  DateTime utc,
  CoarseLocation cell,
) {
  final geocentric = toHorizontal(precess(object.position, utc), utc, cell);
  if (object.id != moonId) return geocentric;
  final parallax = moonPosition(utc).horizontalParallax;
  return Horizontal(
    geocentric.azimuth,
    geocentric.altitude - parallax * _cos(geocentric.altitude),
  );
}

/// A fresh J2000 position for a body that moves, or null for a fixed star.
Equatorial? movingPosition(String id, DateTime utc) {
  if (id == moonId) return moonPosition(utc).position;
  if (!_solarSystemIds.contains(id)) return null;
  return solarSystem(utc).singleWhere((body) => body.id == id).position;
}

const _solarSystemIds = {
  'Sun',
  'Mercury',
  'Venus',
  'Mars',
  'Jupiter',
  'Saturn',
  'Uranus',
  'Neptune',
};
