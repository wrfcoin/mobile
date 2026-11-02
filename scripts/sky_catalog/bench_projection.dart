// ignore_for_file: avoid_print, avoid_relative_lib_imports
// Times the star loop in an ahead-of-time build, the way a release phone runs it.
//   dart compile exe scripts/sky_catalog/bench_projection.dart -o <out> && <out>
import 'dart:typed_data';

import '../../lib/features/sky_view/domain/sky_star_projection.dart';

void main() {
  const stars = 5082;
  final unit = Float32List(stars * 3);
  for (var i = 0; i < stars; i++) {
    // Spread over the sphere: a Fibonacci lattice.
    final z = 1 - 2 * (i + 0.5) / stars;
    final r = _sqrt(1 - z * z);
    final a = i * 2.399963229728653;
    unit[i * 3] = r * _cos(a);
    unit[i * 3 + 1] = r * _sin(a);
    unit[i * 3 + 2] = z;
  }
  final xy = Float32List(stars * 2);
  final watch = Stopwatch()..start();
  var sink = 0.0;
  const frames = 20000;
  for (var f = 0; f < frames; f++) {
    final t = f / frames;
    projectStars(
      unit,
      xy,
      fx: 1 - t,
      fy: t,
      fz: 0.1,
      rx: -t,
      ry: 1 - t,
      rz: 0,
      ux: 0,
      uy: 0.1,
      uz: 1,
      centerX: 195,
      centerY: 422,
      scale: 364,
      minForward: -0.2,
    );
    sink += xy[f % stars];
  }
  watch.stop();
  print(
    '$stars stars: ${(watch.elapsedMicroseconds / frames).toStringAsFixed(1)} '
    'us per frame (sink $sink)',
  );
}

double _sqrt(double v) {
  var x = v < 1e-12 ? 0.0 : 1.0;
  for (var i = 0; i < 30 && x != 0; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}

double _sin(double a) => _cos(a - 1.5707963267948966);

double _cos(double a) {
  final t = a % 6.283185307179586;
  var term = 1.0, sum = 1.0;
  for (var n = 1; n < 14; n++) {
    term *= -t * t / ((2 * n - 1) * (2 * n));
    sum += term;
  }
  return sum;
}
