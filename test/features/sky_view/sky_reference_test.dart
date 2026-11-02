import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/bright_stars.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_catalog.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_astronomy.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_attitude.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_horizon.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_moon.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';

/// Positions checked against real published values. Fixtures come straight from
/// the NASA/JPL Horizons API (https://ssd.jpl.nasa.gov/api/horizons.api), fetched
/// by fixtures/fetch_horizons_altaz.py. See fixtures/README.md.
DateTime _fromJd(num jd) => DateTime.fromMillisecondsSinceEpoch(
  ((jd - 2440587.5) * 86400000).round(),
  isUtc: true,
);

double _separation(double azA, double altA, double azB, double altB) =>
    angularDistance(Equatorial(azA, altA), Equatorial(azB, altB));

void main() {
  final altaz = jsonDecode(
    File('test/features/sky_view/fixtures/horizons_altaz.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final moon = jsonDecode(
    File('test/features/sky_view/fixtures/horizons_moon.json')
        .readAsStringSync(),
  ) as List;

  group('alt-az against Horizons, airless, topocentric', () {
    // Horizons gives apparent airless positions, ours are mean and geometric.
    // Nutation, aberration and light time together are about 0.02 degrees, and
    // JPL's Table 1 elements are the larger part of the budget. Moon: formula
    // error (0.3 degrees) plus a spherical-Earth parallax.
    const tolerance = <String, double>{
      'Sun': 0.1,
      'Moon': 0.5,
      'Venus': 0.3,
      'Mars': 0.3,
      'Jupiter': 0.3,
      'Saturn': 0.3,
    };
    for (final site in altaz.entries) {
      final data = site.value as Map<String, dynamic>;
      final cell = CoarseLocation.round(
        (data['latitude'] as num).toDouble(),
        (data['longitude'] as num).toDouble(),
      );
      for (final body in (data['bodies'] as Map<String, dynamic>).entries) {
        test('${body.key} from ${site.key}', () {
          for (final row in body.value as List) {
            final when = _fromJd(row[0] as num);
            final fix = computeSky(
              when,
              cell,
            ).singleWhere((f) => f.object.id == body.key);
            expect(
              _separation(
                fix.horizontal.azimuth,
                fix.horizontal.altitude,
                (row[1] as num).toDouble(),
                (row[2] as num).toDouble(),
              ),
              lessThan(tolerance[body.key]!),
              reason: 'JD ${row[0]}',
            );
          }
        });
      }
    }
  });

  group('Moon', () {
    test('matches Horizons geocentric J2000 over more than a year', () {
      // 28 samples across a full year of perigees, apogees and node positions.
      expect(moon.length, 28);
      for (final row in moon) {
        final actual = moonPosition(_fromJd(row[0] as num)).position;
        expect(
          angularDistance(
            actual,
            Equatorial((row[1] as num).toDouble(), (row[2] as num).toDouble()),
          ),
          lessThan(0.35),
          reason: 'JD ${row[0]}',
        );
      }
    });

    test('parallax stays in the Moon\'s real range', () {
      for (var day = 0; day < 60; day++) {
        final parallax = moonPosition(
          DateTime.utc(2026).add(Duration(days: day)),
        ).horizontalParallax;
        // 0.90 to 1.02 degrees: distances of about 406,000 down to 356,000 km.
        expect(parallax, inInclusiveRange(0.89, 1.03));
      }
    });

    test('parallax lowers the Moon most at the horizon and not overhead', () {
      final cell = CoarseLocation.round(0, 0);
      final when = DateTime.utc(2026, 11, 1);
      final object = moonObject(when);
      final parallax = moonPosition(when).horizontalParallax;
      final geocentric = toHorizontal(
        precess(object.position, when),
        when,
        cell,
      );
      final observed = observedHorizontal(object, when, cell);
      expect(observed.azimuth, geocentric.azimuth);
      expect(
        geocentric.altitude - observed.altitude,
        inInclusiveRange(0, parallax),
      );
    });

    test(
      'refuses dates outside the same 1800 to 2050 limit as the planets',
      () {
        expect(() => moonPosition(DateTime.utc(2051)), throwsRangeError);
        expect(() => moonPosition(DateTime.utc(1799)), throwsRangeError);
      },
    );

    test('rise and set work for the Moon, about a day apart', () {
      final events = nextHorizonEvents(
        moonObject(DateTime.utc(2026, 11, 1)),
        DateTime.utc(2026, 11, 1),
        CoarseLocation.round(37.8, -122.4),
      )!;
      expect(events.rise, isNotNull);
      expect(events.set, isNotNull);
    });
  });

  group('identities that need no reference table', () {
    final polaris = brightStars.singleWhere((s) => s.name == 'Polaris');

    test('Polaris altitude equals latitude to within its polar distance', () {
      // Spherical trig: a star at polar distance p is within p of the pole, and
      // the pole's altitude is the latitude. Polaris's p comes from the catalog
      // and precession, not from a guessed number, and every hour of the day
      // and every latitude must obey it.
      final when = DateTime.utc(2026, 11, 1);
      final p = 90 - precess(polaris.position, when).dec;
      expect(p, inInclusiveRange(0.5, 0.8));
      for (final latitude in [20.0, 37.8, 51.5, 64.1, 80.0]) {
        final cell = CoarseLocation.round(latitude, -122.4);
        var highest = -90.0, lowest = 90.0;
        for (var minute = 0; minute < 24 * 60; minute += 10) {
          final time = when.add(Duration(minutes: minute));
          final altitude = toHorizontal(
            precess(polaris.position, time),
            time,
            cell,
          ).altitude;
          expect((altitude - latitude).abs(), lessThanOrEqualTo(p + 1e-3));
          highest = altitude > highest ? altitude : highest;
          lowest = lowest < altitude ? lowest : altitude;
        }
        // And over a day it really swings by nearly the full polar distance.
        expect(highest - latitude, closeTo(p, 0.05));
        expect(latitude - lowest, closeTo(p, 0.05));
      }
    });

    test('Polaris is due north within a degree or two at mid latitudes', () {
      final when = DateTime.utc(2026, 11, 1);
      final at = toHorizontal(
        precess(polaris.position, when),
        when,
        CoarseLocation.round(37.8, -122.4),
      );
      expect(((at.azimuth + 180) % 360 - 180).abs(), lessThan(1.5));
    });

    test('map direction agrees with the alt-az it came from', () {
      final fix = computeSky(
        DateTime.utc(2026, 11, 1),
        CoarseLocation.round(37.8, -122.4),
      ).first;
      final direction = Vec3.fromAzAlt(
        fix.horizontal.azimuth,
        fix.horizontal.altitude,
      );
      expect(direction.dot(fix.direction), closeTo(1, 1e-12));
    });

    test('computeSky holds the stars, the Sun, the Moon and seven planets', () {
      final fixes = computeSky(
        DateTime.utc(2026, 11, 1),
        CoarseLocation.round(37.8, -122.4),
      );
      expect(fixes.length, brightStars.length + 1 + 1 + 7);
      expect(fixes.map((f) => f.object.id).toSet().length, fixes.length);
      expect(
        fixes.where((f) => f.isSolarSystem).map((f) => f.object.id).toSet(),
        {
          'Sun',
          'Moon',
          'Mercury',
          'Venus',
          'Mars',
          'Jupiter',
          'Saturn',
          'Uranus',
          'Neptune',
        },
      );
    });
  });
}
