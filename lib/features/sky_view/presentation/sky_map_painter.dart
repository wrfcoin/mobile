import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/sky_catalog.dart';
import '../domain/sky_attitude.dart';
import '../domain/sky_moon.dart';
import '../domain/sky_projection.dart';

const skyBackground = Color(0xFF050B18);
const _ground = Color(0xFF17140F);
const _gridColor = Color(0x2E9FB7D9);
const _horizonColor = Color(0xFF7FB2A0);
const _reticleColor = Color(0xCCFFFFFF);
const _alignColor = Color(0xFFFFC857);

const _planetColors = <String, Color>{
  'Mercury': Color(0xFFCFC6B8),
  'Venus': Color(0xFFFFF4D6),
  'Mars': Color(0xFFFF8A65),
  'Jupiter': Color(0xFFFFE0B2),
  'Saturn': Color(0xFFE6D08A),
  'Uranus': Color(0xFFA7E3E6),
  'Neptune': Color(0xFF8FB4FF),
};

/// Altitude circles and azimuth lines, computed once.
final List<List<Vec3>> _gridLines = [
  for (var alt = 15; alt <= 75; alt += 15)
    [
      for (var az = 0; az <= 360; az += 6)
        Vec3.fromAzAlt(az.toDouble(), alt.toDouble()),
    ],
  for (var az = 0; az < 360; az += 30)
    [
      for (var alt = -75; alt <= 75; alt += 5)
        Vec3.fromAzAlt(az.toDouble(), alt.toDouble()),
    ],
];

const _compassPoints = <(String, double)>[
  ('N', 0),
  ('NE', 45),
  ('E', 90),
  ('SE', 135),
  ('S', 180),
  ('SW', 225),
  ('W', 270),
  ('NW', 315),
];

/// Drawing size in pixels. Stars by catalog magnitude; solar system bodies by a
/// fixed symbol size, because the catalog holds no magnitude for them and the
/// app does not invent one.
double skyObjectRadius(SkyFix fix) {
  if (fix.object.id == 'Sun') return 9;
  if (fix.object.id == moonId) return 8;
  if (fix.isSolarSystem) {
    return const {'Uranus', 'Neptune'}.contains(fix.object.id) ? 2.2 : 4;
  }
  return math.max(1.2, 3.6 - 0.85 * fix.object.magnitude);
}

/// The nearest above-map object to a tap, within reach of a fingertip.
SkyFix? skyObjectAt(
  Offset tap,
  List<SkyFix> fixes,
  SkyPose pose,
  Size size, {
  double reach = 32,
}) {
  final projection = SkyProjection(pose, size);
  SkyFix? best;
  var bestDistance = reach;
  for (final fix in fixes) {
    final at = projection.project(fix.direction);
    if (at == null) continue;
    final distance = (at - tap).distance;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = fix;
    }
  }
  return best;
}

/// Layout-only label cache, so a redraw does not re-shape text.
class SkyLabelCache {
  final _painters = <String, TextPainter>{};

  /// The app theme's font, set from the screen.
  String? fontFamily;
  TextPainter get(String text, Color color, {double size = 11}) =>
      _painters.putIfAbsent('$text/${color.toARGB32()}/$size', () {
        return TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: color,
              fontSize: size,
              fontFamily: fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });
  void dispose() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}

class SkyMapPainter extends CustomPainter {
  final ValueListenable<SkyPose?> pose;
  final List<SkyFix> fixes;
  final bool aligning;
  final SkyLabelCache labels;

  SkyMapPainter({
    required this.pose,
    required this.fixes,
    required this.aligning,
    required this.labels,
  }) : super(repaint: pose);

  static final _gridPaint = Paint()
    ..color = _gridColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.7;
  static final _horizonPaint = Paint()
    ..color = _horizonColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;
  static final _groundPaint = Paint()..color = _ground;
  static final _starPaint = Paint()..color = const Color(0xFFEAF2FF);
  static final _dimPaint = Paint()..color = const Color(0x55EAF2FF);
  static final _outlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = skyBackground);
    final current = pose.value;
    if (current == null) return;
    canvas.clipRect(Offset.zero & size);
    final projection = SkyProjection(current, size);
    _paintGround(canvas, size, projection);
    _paintGrid(canvas, size, projection);
    _paintCompass(canvas, size, projection);
    _paintObjects(canvas, size, projection);
    _paintReticle(canvas, size);
  }

  void _paintGround(Canvas canvas, Size size, SkyProjection projection) {
    final horizon = projection.horizon;
    final screen = Offset.zero & size;
    final radius = horizon.radius;
    if (radius != null) {
      final circle = Rect.fromCircle(center: horizon.point, radius: radius);
      final path = Path()..addOval(circle);
      if (horizon.groundOutside) {
        path
          ..addRect(screen)
          ..fillType = PathFillType.evenOdd;
      }
      canvas.drawPath(path, _groundPaint);
      canvas.drawCircle(horizon.point, radius, _horizonPaint);
      return;
    }
    final zenithward = horizon.zenithward!;
    final along = Offset(-zenithward.dy, zenithward.dx);
    final reach = size.longestSide * 2;
    final a = horizon.point + along * reach, b = horizon.point - along * reach;
    final away = zenithward * -reach;
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(b.dx + away.dx, b.dy + away.dy)
        ..lineTo(a.dx + away.dx, a.dy + away.dy)
        ..close(),
      _groundPaint,
    );
    canvas.drawLine(a, b, _horizonPaint);
  }

  void _paintGrid(Canvas canvas, Size size, SkyProjection projection) {
    final path = Path();
    final limit = size.longestSide * 3;
    for (final line in _gridLines) {
      Offset? previous;
      for (final point in line) {
        final at = projection.project(point);
        // Drop a segment that wraps behind the viewer rather than drawing it
        // straight across the screen.
        final usable = at != null && at.distance < limit;
        if (usable) {
          if (previous == null) {
            path.moveTo(at.dx, at.dy);
          } else {
            path.lineTo(at.dx, at.dy);
          }
        }
        previous = usable ? at : null;
      }
    }
    canvas.drawPath(path, _gridPaint);
  }

  void _paintCompass(Canvas canvas, Size size, SkyProjection projection) {
    for (final (name, azimuth) in _compassPoints) {
      final at = projection.project(Vec3.fromAzAlt(azimuth, 0));
      if (at == null || !(Offset.zero & size).contains(at)) continue;
      final text = labels.get(name, _horizonColor, size: 13);
      text.paint(canvas, at + Offset(-text.width / 2, 3));
    }
  }

  void _paintObjects(Canvas canvas, Size size, SkyProjection projection) {
    final screen = (Offset.zero & size).inflate(12);
    final placed = <Rect>[
      Rect.fromCircle(center: size.center(Offset.zero), radius: 16),
    ];
    final visible = <(SkyFix, Offset)>[];
    for (final fix in fixes) {
      final at = projection.project(fix.direction);
      if (at == null || !screen.contains(at)) continue;
      visible.add((fix, at));
      final radius = skyObjectRadius(fix);
      final below = fix.horizontal.altitude < 0;
      if (fix.isSolarSystem) {
        final color = switch (fix.object.id) {
          'Sun' => const Color(0xFFFFD54F),
          moonId => const Color(0xFFE8E8E0),
          final id => _planetColors[id] ?? Colors.white,
        };
        final fill = Paint()
          ..color = below ? color.withValues(alpha: 0.35) : color;
        canvas.drawCircle(at, radius, fill);
        canvas.drawCircle(
          at,
          radius + 2.5,
          _outlinePaint..color = color.withValues(alpha: below ? 0.2 : 0.55),
        );
      } else {
        canvas.drawCircle(at, radius, below ? _dimPaint : _starPaint);
      }
    }
    // Labels last, solar system and brightest first, so a crowded patch keeps
    // the names people look for.
    visible.sort((a, b) => _labelRank(a.$1).compareTo(_labelRank(b.$1)));
    for (final (fix, at) in visible) {
      if (fix.horizontal.altitude < 0) continue;
      final color = fix.isSolarSystem
          ? (_planetColors[fix.object.id] ?? const Color(0xFFFFF3C4))
          : const Color(0xFFB9C7DE);
      final text = labels.get(fix.object.name, color);
      final radius = skyObjectRadius(fix) + 4;
      final box = Rect.fromLTWH(
        at.dx + radius,
        at.dy - text.height / 2,
        text.width,
        text.height,
      );
      if (placed.any(box.overlaps)) continue;
      placed.add(box);
      text.paint(canvas, box.topLeft);
    }
  }

  double _labelRank(SkyFix fix) =>
      fix.isSolarSystem ? -10 : fix.object.magnitude;

  void _paintReticle(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = aligning ? _alignColor : _reticleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = aligning ? 2 : 1.2;
    canvas.drawCircle(center, 14, paint);
    for (final direction in const [
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      canvas.drawLine(center + direction * 14, center + direction * 22, paint);
    }
  }

  @override
  bool shouldRepaint(SkyMapPainter old) =>
      !identical(old.fixes, fixes) ||
      old.aligning != aligning ||
      !identical(old.pose, pose);
}
