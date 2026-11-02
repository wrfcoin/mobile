// The frame benchmark prints its numbers when asked:
//   flutter test --dart-define=SKY_BENCH=true test/features/sky_view/sky_star_layer_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/bright_stars.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_catalog.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_star_catalog.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_attitude.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_frame.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_projection.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_star_projection.dart';
import 'package:wrfcoin_mobile/features/sky_view/presentation/sky_map_painter.dart';
import 'package:wrfcoin_mobile/features/sky_view/presentation/sky_star_layer.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';

const _bench = bool.fromEnvironment('SKY_BENCH');
const _phone = Size(390, 844);

SkyPose _poseAt(double trueAzimuth, double altitude) {
  final az = -trueAzimuth * math.pi / 360;
  final alt = (90 + altitude) * math.pi / 360;
  return SkyPose.from(
    Quat(
      math.cos(az) * math.cos(alt),
      math.cos(az) * math.sin(alt),
      math.sin(az) * math.sin(alt),
      math.sin(az) * math.cos(alt),
    ),
  );
}

void main() {
  final catalog = SkyStarCatalog.decode(
    ByteData.sublistView(File('assets/sky/sky_catalog.bin').readAsBytesSync()),
  );
  final utc = DateTime.utc(2027, 1, 15, 5);
  final cell = CoarseLocation.round(37.8, -122.4);
  final frame = SkyFrame.at(utc, cell);
  final pose = _poseAt(165, 35);

  test('the flat loop lands where the map projects a direction', () {
    final projection = SkyProjection(pose, _phone);
    final f = frame.toCatalog(pose.forward);
    final r = frame.toCatalog(pose.right);
    final u = frame.toCatalog(pose.up);
    final xy = Float32List(catalog.starCount * 2);
    projectStars(
      catalog.unit,
      xy,
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
      minForward: SkyProjection.minForward,
    );
    var checked = 0;
    for (var i = 0; i < catalog.starCount; i++) {
      final want = projection.project(
        frame.toHorizontal3(
          catalog.unit[i * 3],
          catalog.unit[i * 3 + 1],
          catalog.unit[i * 3 + 2],
        ),
      );
      if (want == null) {
        expect(xy[i * 2].isNaN, isTrue);
        continue;
      }
      checked++;
      expect(xy[i * 2], closeTo(want.dx, 0.01));
      expect(xy[i * 2 + 1], closeTo(want.dy, 0.01));
    }
    expect(checked, greaterThan(1000));
  });

  test('a brighter star beats a slightly nearer faint one, within reach', () {
    final layer = SkyStarLayer(catalog);
    final projection = SkyProjection(pose, _phone);
    final named = {for (final star in brightStars) star.id};
    Offset? at(int i) {
      final direction = frame.toHorizontal3(
        catalog.unit[i * 3],
        catalog.unit[i * 3 + 1],
        catalog.unit[i * 3 + 2],
      );
      return direction.z < 0 ? null : projection.project(direction);
    }

    // Find a real pair on this screen: a bright dot with a faint neighbour.
    Offset? tap;
    int? bright;
    for (var i = 0; i < catalog.starCount && tap == null; i++) {
      if (catalog.magnitude(i) > 4 || named.contains('HR${catalog.hr[i]}')) {
        continue;
      }
      final a = at(i);
      if (a == null || !(Offset.zero & _phone).contains(a)) continue;
      for (var j = i + 1; j < catalog.starCount; j++) {
        if (catalog.magnitude(j) < catalog.magnitude(i) + 1.5) continue;
        final b = at(j);
        if (b == null) continue;
        final gap = (b - a).distance;
        if (gap > 2 && gap < 16) {
          // One pixel nearer the faint star than the bright one.
          tap = (a + b) / 2 + (b - a) / gap * 0.5;
          bright = i;
          break;
        }
      }
    }
    expect(tap, isNotNull, reason: 'the test sky has no such pair');
    expect(layer.starAt(tap!, projection, frame), bright);
    expect(
      layer.starAt(const Offset(-500, -500), projection, frame),
      isNull,
      reason: 'nothing is in reach far off the screen',
    );
    final object = catalog.object(bright!);
    expect(object.id, 'HR${catalog.hr[bright]}');
    expect(object.magnitude, lessThanOrEqualTo(4));
  });

  test('radius falls steadily with magnitude and stays visible', () {
    var last = double.infinity;
    for (var m = -1.5; m <= 6.5; m += 0.5) {
      final r = skyStarRadius(m);
      expect(r, lessThanOrEqualTo(last));
      expect(r, greaterThanOrEqualTo(0.6));
      last = r;
    }
    expect(skyStarRadius(-1.46), greaterThan(skyStarRadius(2)));
    expect(skyStarRadius(2), greaterThan(skyStarRadius(5)));
  });

  test('paints nothing from the catalog when there is no placed sky', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final labels = SkyLabelCache();
    addTearDown(labels.dispose);
    SkyMapPainter(
      pose: ValueNotifier(pose),
      fixes: const [],
      aligning: false,
      labels: labels,
      stars: SkyStarLayer(catalog),
      frame: frame,
    ).paint(canvas, _phone);
    recorder.endRecording().dispose();
  });

  test('frame cost', skip: !_bench, () async {
    final layer = SkyStarLayer(catalog);
    final labels = SkyLabelCache();
    addTearDown(labels.dispose);
    final fixes = computeSky(utc, cell);
    final notifier = ValueNotifier<SkyPose?>(pose);
    final painter = SkyMapPainter(
      pose: notifier,
      fixes: fixes,
      aligning: false,
      labels: labels,
      stars: layer,
      frame: frame,
    );
    const frames = 600;
    ui.Picture record(int f) {
      notifier.value = _poseAt(165 + f * 0.1, 35);
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), _phone);
      return recorder.endRecording();
    }

    final build = Stopwatch()..start();
    for (var f = 0; f < frames; f++) {
      record(f).dispose();
    }
    build.stop();

    // The layer alone, the part this change adds.
    final projection = SkyProjection(pose, _phone);
    final layerOnly = Stopwatch()..start();
    for (var f = 0; f < frames; f++) {
      final recorder = ui.PictureRecorder();
      layer.paint(Canvas(recorder), projection, frame, constellations: true);
      recorder.endRecording().dispose();
    }
    layerOnly.stop();

    final picture = record(0);
    final raster = Stopwatch()..start();
    for (var f = 0; f < 20; f++) {
      final image = await picture.toImage(1170, 2532);
      image.dispose();
    }
    raster.stop();
    picture.dispose();
    // ignore: avoid_print
    print(
      'whole map, record only: ${build.elapsedMicroseconds / frames} us; '
      'star layer: ${layerOnly.elapsedMicroseconds / frames} us; '
      'rasterise on this machine (software, 1170x2532, not scaled): '
      '${raster.elapsedMicroseconds / 20} us',
    );
  });
}
