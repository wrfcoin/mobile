import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/bright_stars.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_star_catalog.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_astronomy.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_attitude.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_frame.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_moon.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';

SkyStarCatalog _load() => SkyStarCatalog.decode(
  ByteData.sublistView(File('assets/sky/$_name').readAsBytesSync()),
);
const _name = 'sky_catalog.bin';

double _ra(String text) {
  final m = RegExp(r'(\d+)h\s*(\d+)m\s*([\d.]+)s').firstMatch(text)!;
  return (int.parse(m[1]!) +
          int.parse(m[2]!) / 60 +
          double.parse(m[3]!) / 3600) *
      15;
}

double _dec(String text) {
  final m = RegExp(r'([+-])(\d+)°\s*(\d+)′\s*(\d+)″').firstMatch(text)!;
  final value =
      int.parse(m[2]!) + int.parse(m[3]!) / 60 + int.parse(m[4]!) / 3600;
  return m[1] == '-' ? -value : value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = _load();
  int star(int hr) => catalog.hr.indexOf(hr);

  test(
    'the app bundle declares the asset, so it loads the way the app does',
    () async {
      final shipped = await loadSkyStarCatalog();
      expect(shipped.starCount, catalog.starCount);
      expect(identical(shipped, await loadSkyStarCatalog()), isTrue);
    },
  );

  test('naked-eye size and the 88 constellations', () {
    expect(catalog.starCount, 5082);
    expect(catalog.hr.toSet().length, catalog.starCount);
    expect(catalog.constellations, hasLength(88));
    expect(
      catalog.constellations.map((c) => c.abbreviation).toSet(),
      hasLength(88),
    );
    expect(catalog.labels, hasLength(89)); // Serpens has two parts.
    final withFigure = catalog.segmentConstellation.toSet();
    expect(withFigure, hasLength(88), reason: 'every constellation has lines');
  });

  test('sampled stars match the raw source text', () {
    final rows = jsonDecode(
      File('test/features/sky_view/fixtures/bsc5_sample.json')
          .readAsStringSync(),
    ) as List;
    expect(rows.length, greaterThan(100));
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final hr = int.parse(row['HR'] as String);
      final i = star(hr);
      expect(i, isNonNegative, reason: 'HR $hr');
      expect(catalog.ra[i], closeTo(_ra(row['RA'] as String), 1e-4));
      expect(catalog.dec[i], closeTo(_dec(row['Dec'] as String), 1e-4));
      expect(catalog.magnitude(i), double.parse(row['Vmag'] as String));
      final name = row['Name'] as String?;
      if (name != null) {
        expect(
          catalog.constellationOf(i).abbreviation,
          name.substring(name.length - 3),
        );
      } else {
        expect(catalog.designation(i), 'HR $hr');
      }
    }
  });

  test('known identities hold', () {
    void check(int hr, String designation, String constellation, double mag) {
      final i = star(hr);
      expect(catalog.designation(i), designation);
      expect(catalog.constellationOf(i).abbreviation, constellation);
      expect(catalog.magnitude(i), mag);
      // The boundaries agree, independently of the star's own name.
      expect(
        catalog.constellationAt(catalog.ra[i], catalog.dec[i])?.abbreviation,
        constellation,
      );
    }

    check(424, '1 α UMi', 'UMi', 2.02); // Polaris
    check(2061, '58 α Ori', 'Ori', 0.50); // Betelgeuse
    check(7001, '3 α Lyr', 'Lyr', 0.03); // Vega
    check(2491, '9 α CMa', 'CMa', -1.46); // Sirius
  });

  test('catalog agrees with the named subset the map labels', () {
    for (final named in brightStars) {
      final i = star(int.parse(named.id.substring(2)));
      expect(i, isNonNegative, reason: named.id);
      expect(catalog.magnitude(i), named.magnitude);
      expect(catalog.ra[i], closeTo(named.position.ra, 1e-3));
      expect(catalog.dec[i], closeTo(named.position.dec, 1e-3));
    }
  });

  test('every figure endpoint in the source is a real catalog star', () {
    final source = jsonDecode(
      File('test/features/sky_view/fixtures/constellation_lines_source.json')
          .readAsStringSync(),
    ) as List;
    double rad(num degrees) => degrees * math.pi / 180;

    /// Degrees from a star in the catalog to a coordinate in the source. Close
    /// double stars need chord lengths from doubles, not the near-1 dot product.
    double miss(int star, List<dynamic> point) {
      final lon = point[0] as num, lat = point[1] as num;
      final ra = catalog.ra[star], dec = catalog.dec[star];
      final dx =
          math.cos(rad(dec)) * math.cos(rad(ra)) -
          math.cos(rad(lat)) * math.cos(rad(lon));
      final dy =
          math.cos(rad(dec)) * math.sin(rad(ra)) -
          math.cos(rad(lat)) * math.sin(rad(lon));
      final dz = math.sin(rad(dec)) - math.sin(rad(lat));
      return math.sqrt(dx * dx + dy * dy + dz * dz) * 180 / math.pi;
    }

    // The asset keeps the source's order, so each segment checks directly.
    var s = 0;
    for (final feature in source.cast<List<dynamic>>()) {
      final id = feature[0] as String;
      for (final line in (feature[1] as List).cast<List<dynamic>>()) {
        for (var p = 0; p + 1 < line.length; p++, s++) {
          final owner = catalog.constellations[catalog.segmentConstellation[s]];
          expect(owner.abbreviation, id);
          final a = catalog.segments[s * 2], b = catalog.segments[s * 2 + 1];
          expect(a, lessThan(catalog.starCount));
          expect(b, lessThan(catalog.starCount));
          expect(miss(a, line[p] as List), lessThan(0.1), reason: '$id $p');
          expect(miss(b, line[p + 1] as List), lessThan(0.1), reason: '$id $p');
        }
      }
    }
    expect(s, catalog.segmentConstellation.length);
  });

  test('the figures join the stars people look for', () {
    bool inFigure(String abbreviation, int hr) {
      final i = star(hr);
      for (var s = 0; s < catalog.segmentConstellation.length; s++) {
        final owner = catalog.constellations[catalog.segmentConstellation[s]];
        if (owner.abbreviation == abbreviation &&
            (catalog.segments[s * 2] == i ||
                catalog.segments[s * 2 + 1] == i)) {
          return true;
        }
      }
      return false;
    }

    expect(inFigure('Ori', 2061), isTrue); // Betelgeuse
    expect(inFigure('Lyr', 7001), isTrue); // Vega
    expect(inFigure('UMi', 424), isTrue); // Polaris
  });

  test('boundaries cover the whole sky once', () {
    var one = 0, none = 0, many = 0;
    // Not on a round number: boundaries run along round coordinates.
    for (var dec = -89.37; dec < 90; dec += 1.13) {
      final steps = math.max(
        8,
        (360 * math.cos(dec * math.pi / 180) / 1.13).round(),
      );
      for (var s = 0; s < steps; s++) {
        final ra = (s + 0.31) * 360 / steps;
        final hits = catalog.boundariesHolding(ra, dec);
        if (hits == 1) {
          one++;
        } else if (hits == 0) {
          none++;
        } else {
          many++;
        }
      }
    }
    expect(one, greaterThan(30000));
    expect(
      none + many,
      lessThan(one ~/ 1000),
      reason: '$none gaps, $many overlaps',
    );
  });

  test('named stars fall inside their own boundaries', () {
    var named = 0, agree = 0;
    for (var i = 0; i < catalog.starCount; i++) {
      if (catalog.designation(i).startsWith('HR ')) continue;
      named++;
      if (catalog.constellationAt(catalog.ra[i], catalog.dec[i]) ==
          catalog.constellationOf(i)) {
        agree++;
      }
    }
    expect(named, greaterThan(2000));
    expect(named - agree, 2); // HR 695 and HR 7724; see the provenance notes.
  });

  test('the shared frame places stars exactly as the per-star calculation', () {
    for (final (utc, cell) in [
      (DateTime.utc(2027, 1, 15, 5), CoarseLocation.round(37.8, -122.4)),
      (DateTime.utc(2049, 7, 2, 21, 13), CoarseLocation.round(-33.9, 151.2)),
      (DateTime.utc(2026, 11, 1), CoarseLocation.round(69.6, 18.9)),
    ]) {
      final frame = SkyFrame.at(utc, cell);
      for (var i = 0; i < catalog.starCount; i += 53) {
        final expected = observedHorizontal(
          SkyObject('', '', '', Equatorial(catalog.ra[i], catalog.dec[i]), 0),
          utc,
          cell,
        );
        final want = Vec3.fromAzAlt(expected.azimuth, expected.altitude);
        final got = frame.toHorizontal3(
          catalog.unit[i * 3],
          catalog.unit[i * 3 + 1],
          catalog.unit[i * 3 + 2],
        );
        final miss = (got + (-want)).length * 180 / math.pi;
        expect(miss, lessThan(1e-4), reason: 'HR ${catalog.hr[i]}');
      }
    }
  });

  test('toCatalog undoes the frame', () {
    final frame = SkyFrame.at(
      DateTime.utc(2027),
      CoarseLocation.round(1.3, 103.8),
    );
    final back = frame.toCatalog(frame.toHorizontal3(0.6, 0, 0.8));
    expect(back.x, closeTo(0.6, 1e-9));
    expect(back.y, closeTo(0, 1e-9));
    expect(back.z, closeTo(0.8, 1e-9));
  });

  test('a damaged file is refused rather than drawn', () {
    final bytes = Uint8List.fromList(
      File('assets/sky/$_name').readAsBytesSync(),
    );
    expect(
      () => SkyStarCatalog.decode(
        ByteData.sublistView(bytes, 0, bytes.length - 1),
      ),
      throwsA(anything),
    );
    bytes[0] = 0;
    expect(
      () => SkyStarCatalog.decode(ByteData.sublistView(bytes)),
      throwsFormatException,
    );
  });
}
