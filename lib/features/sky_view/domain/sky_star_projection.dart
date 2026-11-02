import 'dart:typed_data';

/// Stereographic projection of many unit vectors, the map's hot loop. Same
/// formula as SkyProjection.project, written over flat arrays so a frame
/// allocates nothing however many stars there are. No dart:ui, so it can be
/// timed in an ahead-of-time build (scripts/sky_catalog/bench_projection.dart).
///
/// [unit] holds x, y, z per star; [xy] receives x, y per star, with NaN for any
/// star past [minForward]. The axes are the screen's, expressed in the stars'
/// own frame, so nothing per star depends on the time or the place.
void projectStars(
  Float32List unit,
  Float32List xy, {
  required double fx,
  required double fy,
  required double fz,
  required double rx,
  required double ry,
  required double rz,
  required double ux,
  required double uy,
  required double uz,
  required double centerX,
  required double centerY,
  required double scale,
  required double minForward,
}) {
  final doubled = 2 * scale;
  final count = xy.length >> 1;
  var u = 0;
  for (var i = 0; i < count; i++, u += 3) {
    final x = unit[u], y = unit[u + 1], z = unit[u + 2];
    final forward = x * fx + y * fy + z * fz;
    final out = i << 1;
    if (forward < minForward) {
      xy[out] = double.nan;
      continue;
    }
    final k = doubled / (1 + forward);
    xy[out] = centerX + k * (x * rx + y * ry + z * rz);
    xy[out + 1] = centerY - k * (x * ux + y * uy + z * uz);
  }
}
