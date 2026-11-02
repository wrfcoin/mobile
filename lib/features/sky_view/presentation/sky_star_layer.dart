import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../data/bright_stars.dart';
import '../data/sky_star_catalog.dart';
import '../domain/sky_attitude.dart';
import '../domain/sky_frame.dart';
import '../domain/sky_projection.dart';
import '../domain/sky_star_projection.dart';

/// Drawing size in pixels for a catalog magnitude.
double skyStarRadius(double magnitude) =>
    (3.4 - 0.55 * magnitude).clamp(0.6, 5.0);

/// Faint stars are not drawn through the ground: they only clutter it.
const _belowHorizonLimit = 4.5;

const _bucketLimits = <double>[1, 2, 3, 3.5, 4, 4.5, 5, 5.5, 99];
const _bucketRadiusAt = <double>[
  0.5,
  1.5,
  2.5,
  3.25,
  3.75,
  4.25,
  4.75,
  5.25,
  5.8,
];
const _bucketAlpha = <double>[1, 1, 1, 0.95, 0.9, 0.82, 0.72, 0.62, 0.5];

const _starColor = Color(0xFFEAF2FF);

/// A longer figure segment than any in the data (the longest is 25.6 degrees),
/// so a line with one end off the screen still has both ends projected.
const _segmentMargin = 30 * math.pi / 180;

/// Stars and constellation figures. Every buffer is made once here; a frame
/// only fills them.
class SkyStarLayer {
  final SkyStarCatalog catalog;
  final Float32List _xy;
  final Uint8List _bucket;
  final Float32List _dots, _below, _lines, _dimLines;
  final Int32List _bucketStart, _bucketEnd;
  final List<Paint> _paints;

  static final _belowPaint = Paint()
    ..color = const Color(0x44EAF2FF)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 1.4;
  static final _linePaint = Paint()
    ..color = const Color(0x667FA8D9)
    ..strokeWidth = 0.8;
  static final _dimLinePaint = Paint()
    ..color = const Color(0x267FA8D9)
    ..strokeWidth = 0.8;

  factory SkyStarLayer(SkyStarCatalog catalog) {
    final named = {for (final star in brightStars) star.id};
    final count = catalog.starCount;
    // 255 marks a star the map draws by name, with its details, elsewhere.
    final bucket = Uint8List(count);
    final sizes = Int32List(_bucketLimits.length);
    for (var i = 0; i < count; i++) {
      if (named.contains('HR${catalog.hr[i]}')) {
        bucket[i] = 255;
        continue;
      }
      final magnitude = catalog.magnitude(i);
      var b = 0;
      while (magnitude > _bucketLimits[b]) {
        b++;
      }
      bucket[i] = b;
      sizes[b]++;
    }
    final starts = Int32List(sizes.length);
    var total = 0;
    for (var b = 0; b < sizes.length; b++) {
      starts[b] = total;
      total += sizes[b] * 2;
    }
    final segmentFloats = catalog.segments.length * 2;
    return SkyStarLayer._(
      catalog,
      Float32List(count * 2),
      bucket,
      Float32List(total),
      Float32List(total),
      Float32List(segmentFloats),
      Float32List(segmentFloats),
      starts,
      Int32List(sizes.length),
      [
        for (var b = 0; b < sizes.length; b++)
          Paint()
            ..color = _starColor.withValues(alpha: _bucketAlpha[b])
            ..strokeCap = StrokeCap.round
            ..strokeWidth = skyStarRadius(_bucketRadiusAt[b]) * 2,
      ],
    );
  }

  SkyStarLayer._(
    this.catalog,
    this._xy,
    this._bucket,
    this._dots,
    this._below,
    this._lines,
    this._dimLines,
    this._bucketStart,
    this._bucketEnd,
    this._paints,
  );

  /// Stars further from the screen's centre than this cannot affect the frame.
  double _minForward(Size size, double scale) {
    final corner = size.longestSide == 0
        ? 0.0
        : math.sqrt(size.width * size.width + size.height * size.height) / 2;
    final angle = 2 * math.atan(corner / (2 * scale)) + _segmentMargin;
    return math.max(
      SkyProjection.minForward,
      math.cos(math.min(angle, math.pi)),
    );
  }

  void _project(SkyProjection projection, SkyFrame frame) {
    final pose = projection.pose;
    final f = frame.toCatalog(pose.forward);
    final r = frame.toCatalog(pose.right);
    final u = frame.toCatalog(pose.up);
    projectStars(
      catalog.unit,
      _xy,
      fx: f.x,
      fy: f.y,
      fz: f.z,
      rx: r.x,
      ry: r.y,
      rz: r.z,
      ux: u.x,
      uy: u.y,
      uz: u.z,
      centerX: projection.center.dx,
      centerY: projection.center.dy,
      scale: projection.scale,
      minForward: _minForward(projection.size, projection.scale),
    );
  }

  void paint(
    Canvas canvas,
    SkyProjection projection,
    SkyFrame frame, {
    required bool constellations,
  }) {
    _project(projection, frame);
    final size = projection.size;
    // The zenith, in the catalog's frame, tells above from below the horizon.
    final zenith = frame.toCatalog(const Vec3(0, 0, 1));
    if (constellations) _paintLines(canvas, size, zenith);
    _paintDots(canvas, size, zenith);
  }

  void _paintLines(Canvas canvas, Size size, Vec3 zenith) {
    final segments = catalog.segments;
    final unit = catalog.unit;
    final xy = _xy;
    final width = size.width, height = size.height;
    final zx = zenith.x, zy = zenith.y, zz = zenith.z;
    var bright = 0, dim = 0;
    for (var s = 0; s < segments.length; s += 2) {
      final a = segments[s], b = segments[s + 1];
      final ax = xy[a << 1], bx = xy[b << 1];
      if (ax.isNaN || bx.isNaN) continue;
      final ay = xy[(a << 1) + 1], by = xy[(b << 1) + 1];
      if ((ax < 0 && bx < 0) ||
          (ax > width && bx > width) ||
          (ay < 0 && by < 0) ||
          (ay > height && by > height)) {
        continue;
      }
      final a3 = a * 3, b3 = b * 3;
      final above =
          unit[a3] * zx + unit[a3 + 1] * zy + unit[a3 + 2] * zz >= 0 ||
          unit[b3] * zx + unit[b3 + 1] * zy + unit[b3 + 2] * zz >= 0;
      if (above) {
        _lines[bright] = ax;
        _lines[bright + 1] = ay;
        _lines[bright + 2] = bx;
        _lines[bright + 3] = by;
        bright += 4;
      } else {
        _dimLines[dim] = ax;
        _dimLines[dim + 1] = ay;
        _dimLines[dim + 2] = bx;
        _dimLines[dim + 3] = by;
        dim += 4;
      }
    }
    if (dim > 0) {
      canvas.drawRawPoints(
        PointMode.lines,
        Float32List.sublistView(_dimLines, 0, dim),
        _dimLinePaint,
      );
    }
    if (bright > 0) {
      canvas.drawRawPoints(
        PointMode.lines,
        Float32List.sublistView(_lines, 0, bright),
        _linePaint,
      );
    }
  }

  void _paintDots(Canvas canvas, Size size, Vec3 zenith) {
    final unit = catalog.unit;
    final xy = _xy;
    final bucket = _bucket;
    final dots = _dots;
    final ends = _bucketEnd;
    final width = size.width, height = size.height;
    final zx = zenith.x, zy = zenith.y, zz = zenith.z;
    ends.setAll(0, _bucketStart);
    var below = 0;
    final count = catalog.starCount;
    final faintBelow = _firstFainterThan(_belowHorizonLimit);
    for (var i = 0; i < count; i++) {
      final b = bucket[i];
      if (b == 255) continue;
      final x = xy[i << 1];
      if (x.isNaN || x < -2 || x > width + 2) continue;
      final y = xy[(i << 1) + 1];
      if (y < -2 || y > height + 2) continue;
      final i3 = i * 3;
      if (unit[i3] * zx + unit[i3 + 1] * zy + unit[i3 + 2] * zz >= 0) {
        final end = ends[b];
        dots[end] = x;
        dots[end + 1] = y;
        ends[b] = end + 2;
      } else if (i < faintBelow) {
        _below[below] = x;
        _below[below + 1] = y;
        below += 2;
      }
    }
    if (below > 0) {
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(_below, 0, below),
        _belowPaint,
      );
    }
    for (var b = 0; b < ends.length; b++) {
      if (ends[b] == _bucketStart[b]) continue;
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(dots, _bucketStart[b], ends[b]),
        _paints[b],
      );
    }
  }

  int? _faintBelow;
  int _firstFainterThan(double limit) => _faintBelow ??= () {
    var i = 0;
    while (i < catalog.starCount && catalog.magnitude(i) <= limit) {
      i++;
    }
    return i;
  }();

  /// The drawn star a tap most likely means: nearest, with a brighter star
  /// allowed to be a little further than a faint one, since it is what the eye
  /// went to. Stars drawn by name are not considered here.
  int? starAt(
    Offset tap,
    SkyProjection projection,
    SkyFrame frame, {
    double reach = 24,
  }) {
    _project(projection, frame);
    final zenith = frame.toCatalog(const Vec3(0, 0, 1));
    final faintBelow = _firstFainterThan(_belowHorizonLimit);
    int? best;
    var bestScore = double.infinity;
    for (var i = 0; i < catalog.starCount; i++) {
      if (_bucket[i] == 255) continue;
      final x = _xy[i << 1];
      if (x.isNaN) continue;
      final dx = x - tap.dx, dy = _xy[(i << 1) + 1] - tap.dy;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > reach) continue;
      final i3 = i * 3;
      final above =
          catalog.unit[i3] * zenith.x +
              catalog.unit[i3 + 1] * zenith.y +
              catalog.unit[i3 + 2] * zenith.z >=
          0;
      if (!above && i >= faintBelow) continue;
      final score = distance + 2 * catalog.magnitude(i);
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }
}
