import 'dart:math' as math;

/// Tilt-compensated accelerometer/magnetometer fallback, in device coordinates:
/// x right, y top, z out of screen. Point along the rear-facing normal (-z).
/// Declination is east-positive; caller must supply a known correction.
/// This is not a fused rotation vector and does not estimate sensor accuracy.
({double azimuth, double altitude})? skyOrientation(
  List<double> gravity,
  List<double> magnetic,
  double declination,
) {
  if (gravity.length != 3 ||
      magnetic.length != 3 ||
      ![...gravity, ...magnetic, declination].every((v) => v.isFinite) ||
      declination.abs() > 180) {
    return null;
  }
  double length(List<double> v) => math.sqrt(v.fold(0.0, (s, x) => s + x * x));
  final g = length(gravity), m = length(magnetic);
  // Reject free fall, strong acceleration, missing fields and nearby magnets.
  if (g < 7 || g > 12 || m < 15 || m > 100) return null;
  final up = gravity.map((v) => v / g).toList();
  List<double> cross(List<double> a, List<double> b) => [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
  final rawEast = cross(magnetic, up);
  final eastLength = length(rawEast);
  if (eastLength / m < 0.1) return null; // near-parallel: heading indeterminate
  final east = rawEast.map((v) => v / eastLength).toList();
  final north = cross(up, east);
  return (
    azimuth:
        (math.atan2(-east[2], -north[2]) * 180 / math.pi + declination) % 360,
    altitude: math.asin((-up[2]).clamp(-1, 1)) * 180 / math.pi,
  );
}
