import 'dart:math' as math;

import '../data/wmm2025_coefficients.dart';

/// Magnetic field at a point, from the World Magnetic Model.
class WmmField {
  /// East-positive angle from true north to magnetic north, in degrees.
  final double declination;
  final double inclination;

  /// Horizontal and total intensity, in nanotesla.
  final double horizontal, total;

  const WmmField({
    required this.declination,
    required this.inclination,
    required this.horizontal,
    required this.total,
  });

  /// NOAA's "blackout zone" limit: below this the compass is unreliable.
  static const unreliableHorizontalNt = 2000.0;
  bool get compassUnreliable => horizontal < unreliableHorizontalNt;
}

const _lastValidYear = 2030.0;
const _maxDegree = 12;

/// Fractional year, the way the WMM software counts it.
double wmmDecimalYear(DateTime when) {
  final utc = when.toUtc();
  final start = DateTime.utc(utc.year);
  final end = DateTime.utc(utc.year + 1);
  return utc.year +
      utc.difference(start).inMicroseconds /
          end.difference(start).inMicroseconds;
}

/// Evaluates WMM2025 offline, following the equations in the WMM2025 technical
/// report (Chulliat et al., NOAA/NCEI). [latitude] and [longitude] are geodetic
/// degrees, [altitudeKm] above the WGS84 ellipsoid.
///
/// Returns null outside 2025.0 to 2030.0 or for bad input: the model is not
/// valid there, and an extrapolated correction would look true without being so.
WmmField? wmmField(
  double latitude,
  double longitude,
  double year, {
  double altitudeKm = 0,
}) {
  if (![latitude, longitude, year, altitudeKm].every((v) => v.isFinite) ||
      latitude.abs() > 90 ||
      longitude.abs() > 180 ||
      year < wmmEpoch ||
      year > _lastValidYear) {
    return null;
  }
  const a = 6378.137, f = 1 / 298.257223563, referenceRadius = 6371.2;
  const e2 = f * (2 - f);
  const degree = math.pi / 180;
  final phi = latitude * degree, lambda = longitude * degree;
  final sinPhi = math.sin(phi), cosPhi = math.cos(phi);

  // Geodetic to geocentric spherical (report equation 7).
  final curvature = a / math.sqrt(1 - e2 * sinPhi * sinPhi);
  final p = (curvature + altitudeKm) * cosPhi;
  final z = (curvature * (1 - e2) + altitudeKm) * sinPhi;
  final r = math.sqrt(p * p + z * z);
  final phiPrime = math.asin(z / r);
  // Colatitude terms. The longitude term below divides by sinTheta, which is
  // clamped so a cell at the exact geographic pole stays finite.
  final cosTheta = math.sin(phiPrime);
  final sinTheta = math.max(math.cos(phiPrime), 1e-9);

  // Schmidt semi-normalised associated Legendre functions and d/d(theta).
  final pnm = List.generate(
    _maxDegree + 1,
    (_) => List.filled(_maxDegree + 1, 0.0),
  );
  final dpnm = List.generate(
    _maxDegree + 1,
    (_) => List.filled(_maxDegree + 1, 0.0),
  );
  pnm[0][0] = 1;
  for (var n = 1; n <= _maxDegree; n++) {
    final k = n == 1 ? 1.0 : math.sqrt((2 * n - 1) / (2 * n));
    pnm[n][n] = k * sinTheta * pnm[n - 1][n - 1];
    dpnm[n][n] =
        k * (cosTheta * pnm[n - 1][n - 1] + sinTheta * dpnm[n - 1][n - 1]);
    for (var m = 0; m < n; m++) {
      final b = math.sqrt((n * n - m * m).toDouble());
      final c = n >= 2
          ? math.sqrt(((n - 1) * (n - 1) - m * m).toDouble())
          : 0.0;
      final previous = n >= 2 ? pnm[n - 2][m] : 0.0;
      final dPrevious = n >= 2 ? dpnm[n - 2][m] : 0.0;
      pnm[n][m] = ((2 * n - 1) * cosTheta * pnm[n - 1][m] - c * previous) / b;
      dpnm[n][m] =
          ((2 * n - 1) *
                  (cosTheta * dpnm[n - 1][m] - sinTheta * pnm[n - 1][m]) -
              c * dPrevious) /
          b;
    }
  }

  final dt = year - wmmEpoch;
  var xPrime = 0.0, yPrime = 0.0, zPrime = 0.0;
  for (final row in wmm2025Coefficients) {
    final n = row[0].toInt(), m = row[1].toInt();
    final g = row[2] + dt * row[4];
    final h = row[3] + dt * row[5];
    final scale = math.pow(referenceRadius / r, n + 2).toDouble();
    final cosM = math.cos(m * lambda), sinM = math.sin(m * lambda);
    final mix = g * cosM + h * sinM;
    // The report's X' is -sum(... dP/dphi'), and dP/dphi' = -dP/dtheta.
    xPrime += scale * mix * dpnm[n][m];
    yPrime += scale * m * (g * sinM - h * cosM) * pnm[n][m] / sinTheta;
    zPrime -= (n + 1) * scale * mix * pnm[n][m];
  }

  // Back to the ellipsoidal frame (report equation 17).
  final tilt = phiPrime - phi;
  final x = xPrime * math.cos(tilt) - zPrime * math.sin(tilt);
  final y = yPrime;
  final down = xPrime * math.sin(tilt) + zPrime * math.cos(tilt);
  final horizontal = math.sqrt(x * x + y * y);
  return WmmField(
    declination: math.atan2(y, x) / degree,
    inclination: math.atan2(down, horizontal) / degree,
    horizontal: horizontal,
    total: math.sqrt(horizontal * horizontal + down * down),
  );
}

/// East-positive declination for a date, or null when the model does not apply.
double? wmmDeclination(double latitude, double longitude, DateTime when) =>
    wmmField(latitude, longitude, wmmDecimalYear(when))?.declination;
