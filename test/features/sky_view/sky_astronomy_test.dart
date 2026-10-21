import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_astronomy.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/bright_stars.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';

void main() {
  final epoch = DateTime.utc(2000, 1, 1, 12);
  test('UTC epochs and east-positive sidereal longitude', () {
    expect(julianDay(epoch), 2451545);
    expect(siderealDegrees(epoch, 0), closeTo(280.46061837, 1e-7));
    expect(siderealDegrees(epoch, 15), closeTo(295.46061837, 1e-7));
    expect(julianDay(epoch.toLocal()), julianDay(epoch));
  });
  test('equator horizon: meridian zenith, east rise and west set', () {
    final cell = CoarseLocation.round(0, 0);
    final lst = siderealDegrees(epoch, 0);
    expect(
      toHorizontal(Equatorial(lst, 0), epoch, cell).altitude,
      closeTo(90, 1e-6),
    );
    final east = toHorizontal(Equatorial(lst + 90, 0), epoch, cell);
    final west = toHorizontal(Equatorial(lst - 90, 0), epoch, cell);
    expect(east.azimuth, closeTo(90, 1e-6));
    expect(west.azimuth, closeTo(270, 1e-6));
    expect(east.altitude, closeTo(0, 1e-6));
    expect(
      toHorizontal(Equatorial(lst + 180, 0), epoch, cell).altitude,
      closeTo(-90, 1e-6),
    );
  });
  test('precession moves J2000 coordinates to the date, identity at epoch', () {
    const point = Equatorial(0, 0);
    expect(precess(point, epoch).ra, closeTo(0, 1e-9));
    final moved = precess(point, DateTime.utc(2050, 1, 1, 12));
    expect(moved.ra, closeTo(0.6407, 0.0002));
    expect(moved.dec, closeTo(0.2783, 0.0002));
  });
  test('bundled catalog has genuine IDs, finite angles and a known Sirius', () {
    expect(brightStars.length, 93);
    expect(brightStars.map((s) => s.id).toSet().length, brightStars.length);
    for (final star in brightStars) {
      expect(star.position.ra, inInclusiveRange(0, 360));
      expect(star.position.dec, inInclusiveRange(-90, 90));
      expect(star.magnitude, lessThanOrEqualTo(2.5));
    }
    final sirius = brightStars.singleWhere((s) => s.id == 'HR2491');
    expect(sirius.position.ra, closeTo(101.287, 0.001));
    expect(sirius.position.dec, closeTo(-16.716, 0.001));
  });
  final vectors = jsonDecode(
    File('test/features/sky_view/fixtures/horizons.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final body in vectors.entries) {
    for (final row in body.value as List) {
      test('${body.key} matches independent Horizons at JD${row[0]}', () {
        final date = DateTime.fromMillisecondsSinceEpoch(
          (((row[0] as num) - 2440587.5) * 86400000).round(),
          isUtc: true,
        );
        final actual = solarSystem(date).singleWhere((s) => s.name == body.key);
        expect(
          angularDistance(
            actual.position,
            Equatorial((row[1] as num).toDouble(), (row[2] as num).toDouble()),
          ),
          lessThan(0.6),
        );
      });
    }
  }
  test('invalid epoch and location never produce plausible objects', () {
    expect(() => solarSystem(DateTime.utc(2051)), throwsRangeError);
    expect(() => solarSystem(DateTime.utc(1799)), throwsRangeError);
    expect(
      () => toHorizontal(
        const Equatorial(0, 0),
        epoch,
        CoarseLocation.round(91, 0),
      ),
      throwsRangeError,
    );
  });
  test('horizon uses the coarse cell, handles poles without NaN', () {
    final a = toHorizontal(
      const Equatorial(45, 30),
      epoch,
      CoarseLocation.round(12.341, 23.441),
    );
    final b = toHorizontal(
      const Equatorial(45, 30),
      epoch,
      CoarseLocation.round(12.349, 23.449),
    );
    expect(a.azimuth, b.azimuth);
    expect(a.altitude, b.altitude);
    expect(
      toHorizontal(
        const Equatorial(45, 30),
        epoch,
        CoarseLocation.round(90, 0),
      ).altitude,
      closeTo(30, 1e-6),
    );
  });
}
