import 'dart:math' as math;

import '../../weather/domain/models/coarse_location.dart';

const _radians = math.pi / 180;
double _sin(double degrees) => math.sin(degrees * _radians);
double _cos(double degrees) => math.cos(degrees * _radians);
double _asin(double value) => math.asin(value.clamp(-1, 1)) / _radians;
double _atan(double y, double x) => math.atan2(y, x) / _radians;
double normalizeDegrees(double value) => value % 360;

/// Mean J2000 equatorial angles, in degrees, unless explicitly precessed.
class Equatorial {
  final double ra, dec;
  const Equatorial(this.ra, this.dec);
}

class Horizontal {
  /// True north = 0, east = 90; geometric altitude (no refraction).
  final double azimuth, altitude;
  const Horizontal(this.azimuth, this.altitude);
}

class SkyObject {
  final String id, name, constellation;
  final Equatorial position;
  final double magnitude;
  const SkyObject(
    this.id,
    this.name,
    this.constellation,
    this.position,
    this.magnitude,
  );
}

double julianDay(DateTime utc) =>
    utc.microsecondsSinceEpoch / Duration.microsecondsPerDay + 2440587.5;

double siderealDegrees(DateTime utc, double eastLongitude) {
  final d = julianDay(utc) - 2451545;
  final t = d / 36525;
  return normalizeDegrees(
    280.46061837 +
        360.98564736629 * d +
        0.000387933 * t * t -
        t * t * t / 38710000 +
        eastLongitude,
  );
}

/// IAU 1976 mean precession from J2000 to the date. Adequate for this finder.
Equatorial precess(Equatorial point, DateTime utc) {
  final t = (julianDay(utc) - 2451545) / 36525;
  final zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) / 3600;
  final z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) / 3600;
  final theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) / 3600;
  final a = _cos(point.dec) * _sin(point.ra + zeta);
  final b =
      _cos(theta) * _cos(point.dec) * _cos(point.ra + zeta) -
      _sin(theta) * _sin(point.dec);
  final c =
      _sin(theta) * _cos(point.dec) * _cos(point.ra + zeta) +
      _cos(theta) * _sin(point.dec);
  return Equatorial(normalizeDegrees(_atan(a, b) + z), _asin(c));
}

/// Input equatorial coordinates must already be in the mean frame of the date.
Horizontal toHorizontal(Equatorial point, DateTime utc, CoarseLocation cell) {
  if (!cell.latitude.isFinite ||
      !cell.longitude.isFinite ||
      cell.latitude.abs() > 90 ||
      cell.longitude.abs() > 180) {
    throw RangeError('Invalid coarse sky location');
  }
  final h = siderealDegrees(utc, cell.longitude) - point.ra;
  final east = -_cos(point.dec) * _sin(h);
  final north =
      _sin(point.dec) * _cos(cell.latitude) -
      _cos(point.dec) * _cos(h) * _sin(cell.latitude);
  final up =
      _sin(point.dec) * _sin(cell.latitude) +
      _cos(point.dec) * _cos(h) * _cos(cell.latitude);
  return Horizontal(normalizeDegrees(_atan(east, north)), _asin(up));
}

double angularDistance(Equatorial a, Equatorial b) =>
    math.acos(
      (_sin(a.dec) * _sin(b.dec) +
              _cos(a.dec) * _cos(b.dec) * _cos(a.ra - b.ra))
          .clamp(-1, 1),
    ) /
    _radians;

// JPL Table 1: a, e, I, L, longitude of perihelion, node; then century rates.
// https://ssd.jpl.nasa.gov/planets/approx_pos.html (1800–2050).
const _elements = <String, List<double>>{
  'Mercury': [
    .38709927,
    .20563593,
    7.00497902,
    252.25032350,
    77.45779628,
    48.33076593,
    .00000037,
    .00001906,
    -.00594749,
    149472.67411175,
    .16047689,
    -.12534081,
  ],
  'Venus': [
    .72333566,
    .00677672,
    3.39467605,
    181.97909950,
    131.60246718,
    76.67984255,
    .00000390,
    -.00004107,
    -.00078890,
    58517.81538729,
    .00268329,
    -.27769418,
  ],
  'Earth': [
    1.00000261,
    .01671123,
    -.00001531,
    100.46457166,
    102.93768193,
    0,
    .00000562,
    -.00004392,
    -.01294668,
    35999.37244981,
    .32327364,
    0,
  ],
  'Mars': [
    1.52371034,
    .09339410,
    1.84969142,
    -4.55343205,
    -23.94362959,
    49.55953891,
    .00001847,
    .00007882,
    -.00813131,
    19140.30268499,
    .44441088,
    -.29257343,
  ],
  'Jupiter': [
    5.20288700,
    .04838624,
    1.30439695,
    34.39644051,
    14.72847983,
    100.47390909,
    -.00011607,
    -.00013253,
    -.00183714,
    3034.74612775,
    .21252668,
    .20469106,
  ],
  'Saturn': [
    9.53667594,
    .05386179,
    2.48599187,
    49.95424423,
    92.59887831,
    113.66242448,
    -.00125060,
    -.00050991,
    .00193609,
    1222.49362201,
    -.41897216,
    -.28867794,
  ],
  'Uranus': [
    19.18916464,
    .04725744,
    .77263783,
    313.23810451,
    170.95427630,
    74.01692503,
    -.00196176,
    -.00004397,
    -.00242939,
    428.48202785,
    .40805281,
    .04240589,
  ],
  'Neptune': [
    30.06992276,
    .00859048,
    1.77004347,
    -55.12002969,
    44.96476227,
    131.78422574,
    .00026291,
    .00005105,
    .00035372,
    218.45945325,
    -.32241464,
    -.00508664,
  ],
};

List<double> _heliocentric(List<double> elements, double t) {
  final p = List.generate(6, (i) => elements[i] + elements[i + 6] * t);
  final a = p[0], e = p[1], inclination = p[2], node = p[5];
  final w = p[4] - node;
  final mean = ((p[3] - p[4] + 180) % 360 - 180) * _radians;
  var eccentric = mean;
  for (var i = 0; i < 20; i++) {
    final delta =
        (eccentric - e * math.sin(eccentric) - mean) /
        (1 - e * math.cos(eccentric));
    eccentric -= delta;
    if (delta.abs() < 1e-12) break;
  }
  final x = a * (math.cos(eccentric) - e);
  final y = a * math.sqrt(1 - e * e) * math.sin(eccentric);
  return [
    (_cos(w) * _cos(node) - _sin(w) * _sin(node) * _cos(inclination)) * x +
        (-_sin(w) * _cos(node) - _cos(w) * _sin(node) * _cos(inclination)) * y,
    (_cos(w) * _sin(node) + _sin(w) * _cos(node) * _cos(inclination)) * x +
        (-_sin(w) * _sin(node) + _cos(w) * _cos(node) * _cos(inclination)) * y,
    _sin(w) * _sin(inclination) * x + _cos(w) * _sin(inclination) * y,
  ];
}

/// Geocentric, approximate J2000 positions; no network or clock reads.
/// Sun plus seven planets, not the Moon. Valid only for years 1800–2050.
List<SkyObject> solarSystem(DateTime utc) {
  final year = utc.toUtc().year;
  if (year < 1800 || year > 2050) {
    throw RangeError('Ephemeris supports 1800–2050');
  }
  final t = (julianDay(utc) - 2451545) / 36525;
  final earth = _heliocentric(_elements['Earth']!, t);
  final objects = <SkyObject>[];
  for (final name in ['Sun', ..._elements.keys.where((n) => n != 'Earth')]) {
    final body = name == 'Sun'
        ? [0.0, 0.0, 0.0]
        : _heliocentric(_elements[name]!, t);
    final x = body[0] - earth[0];
    final y = body[1] - earth[1];
    final z = body[2] - earth[2];
    final ey = _cos(23.43928) * y - _sin(23.43928) * z;
    final ez = _sin(23.43928) * y + _cos(23.43928) * z;
    objects.add(
      SkyObject(
        name,
        name,
        '',
        Equatorial(
          normalizeDegrees(_atan(ey, x)),
          _atan(ez, math.sqrt(x * x + ey * ey)),
        ),
        double.nan,
      ),
    ); // Do not invent an apparent magnitude for planets.
  }
  return objects;
}
