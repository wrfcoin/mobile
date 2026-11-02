import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/wmm.dart';

/// Official NOAA/NCEI check values, shipped with the model in WMM2025COF.zip:
/// WMM2025_TestValues.txt (provenance: docs/licenses/wmm2025-provenance.md).
/// Columns: year, altitude km, latitude, longitude, D, I, H, X, Y, Z, F, ...
void main() {
  final rows = File('test/features/sky_view/fixtures/WMM2025_TestValues.txt')
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty && !line.startsWith('#'))
      .map(
        (line) => line.trim().split(RegExp(r'\s+')).map(double.parse).toList(),
      )
      .toList();

  test('the table is the full official one', () {
    expect(rows.length, 100);
    expect(rows.map((r) => r[0]).toSet(), hasLength(10));
  });

  test('every official row matches: D and I to the table\'s 0.01 degree', () {
    for (final row in rows) {
      final field = wmmField(row[2], row[3], row[0], altitudeKm: row[1])!;
      final at = 'year ${row[0]} alt ${row[1]} lat ${row[2]} lon ${row[3]}';
      expect(field.declination, closeTo(row[4], 0.0051), reason: at);
      expect(field.inclination, closeTo(row[5], 0.0051), reason: at);
    }
  });

  test('every official row matches: H and F to 0.01 nT', () {
    for (final row in rows) {
      final field = wmmField(row[2], row[3], row[0], altitudeKm: row[1])!;
      expect(field.horizontal, closeTo(row[6], 0.01));
      expect(field.total, closeTo(row[10], 0.01));
    }
  });

  test('refuses to extrapolate outside the model\'s five years', () {
    expect(wmmField(40, -100, 2024.99), isNull);
    expect(wmmField(40, -100, 2030.01), isNull);
    expect(wmmDeclination(40, -100, DateTime.utc(2031)), isNull);
    expect(wmmField(40, -100, 2030.0), isNotNull);
  });

  test('bad input returns null', () {
    expect(wmmField(double.nan, 0, 2026), isNull);
    expect(wmmField(91, 0, 2026), isNull);
    expect(wmmField(0, 181, 2026), isNull);
    expect(wmmField(0, 0, double.infinity), isNull);
  });

  test('stays finite at the exact geographic poles', () {
    for (final lat in [90.0, -90.0]) {
      for (final lon in [-180.0, 0.0, 77.0]) {
        final field = wmmField(lat, lon, 2026)!;
        expect(field.declination.isFinite, isTrue);
        expect(field.total, greaterThan(40000));
      }
    }
  });

  test('flags the blackout zone near the magnetic pole', () {
    // The first official row (89 N, -121) has H of 1504 nT, under NOAA's limit.
    expect(wmmField(89, -121, 2025)!.compassUnreliable, isTrue);
    expect(wmmField(40, -100, 2026)!.compassUnreliable, isFalse);
  });

  test('decimal year starts at New Year and is halfway at mid-year', () {
    expect(wmmDecimalYear(DateTime.utc(2026)), 2026);
    // 2026 has 365 days, so 182.5 days in is exactly half.
    expect(wmmDecimalYear(DateTime.utc(2026, 7, 2, 12)), closeTo(2026.5, 1e-9));
  });
}
