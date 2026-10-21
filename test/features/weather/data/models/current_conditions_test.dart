import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/weather_envelopes.dart';

/// mobile#332: `GET /weather/current/:lat,lon` (backend#1304) maps to
/// nullable readings. A real 0 stays 0; an absent value stays null.
Map<String, Object?> _envelope(Map<String, Object?> current) => {
  'location': {'latitude': 45.0, 'longitude': -93.3, 'name': '45.0,-93.3'},
  'current': current,
  'source': 'NOAA-NWS',
  'timestamp': '2026-09-29T17:00:00.000Z',
  'status': 'success',
};

void main() {
  group('currentFromEnvelope', () {
    test('maps present values', () {
      final c = currentFromEnvelope(
        _envelope({
          'temperatureC': 19,
          'relativeHumidityPercent': 68.2,
          'barometricPressureHpa': 1009.82,
          'seaLevelPressureHpa': null,
          'windSpeedKmh': 11.12,
          'observedAt': '2026-09-29T16:45:00+00:00',
        }),
      )!;
      expect(c.temperatureC, 19);
      expect(c.relativeHumidityPercent, 68.2);
      expect(c.barometricPressureHpa, 1009.82);
      expect(c.seaLevelPressureHpa, isNull);
      expect(c.windSpeedKmh, 11.12);
      expect(c.observedAt, '2026-09-29T16:45:00+00:00');
    });

    test('null stays null, never 0', () {
      final c = currentFromEnvelope(
        _envelope({
          'temperatureC': null,
          'relativeHumidityPercent': null,
          'barometricPressureHpa': null,
          'seaLevelPressureHpa': null,
          'windSpeedKmh': null,
          'observedAt': null,
        }),
      )!;
      expect(c.temperatureC, isNull);
      expect(c.relativeHumidityPercent, isNull);
      expect(c.barometricPressureHpa, isNull);
      expect(c.seaLevelPressureHpa, isNull);
      expect(c.windSpeedKmh, isNull);
      expect(c.observedAt, isNull);
      expect(c.pressureHpa, isNull);
    });

    test('missing keys are null', () {
      final c = currentFromEnvelope(_envelope({}))!;
      expect(c.relativeHumidityPercent, isNull);
      expect(c.pressureHpa, isNull);
    });

    test('a real 0 stays 0', () {
      final c = currentFromEnvelope(
        _envelope({
          'temperatureC': 0,
          'relativeHumidityPercent': 0,
          'barometricPressureHpa': 0,
          'windSpeedKmh': 0,
        }),
      )!;
      expect(c.temperatureC, 0);
      expect(c.relativeHumidityPercent, 0);
      expect(c.barometricPressureHpa, 0);
      expect(c.pressureHpa, 0, reason: 'a barometric 0 is not "missing"');
      expect(c.windSpeedKmh, 0);
    });

    test('pressure prefers barometric, falls back to sea-level', () {
      final both = currentFromEnvelope(
        _envelope({
          'barometricPressureHpa': 1009.8,
          'seaLevelPressureHpa': 1013.2,
        }),
      )!;
      expect(both.pressureHpa, 1009.8);
      final seaOnly = currentFromEnvelope(
        _envelope({
          'barometricPressureHpa': null,
          'seaLevelPressureHpa': 1013.2,
        }),
      )!;
      expect(seaOnly.pressureHpa, 1013.2);
    });

    test('non-numeric values are null', () {
      final c = currentFromEnvelope(
        _envelope({'relativeHumidityPercent': '68', 'observedAt': 5}),
      )!;
      expect(c.relativeHumidityPercent, isNull);
      expect(c.observedAt, isNull);
    });

    test('not the envelope: null', () {
      expect(currentFromEnvelope(null), isNull);
      expect(currentFromEnvelope('x'), isNull);
      expect(currentFromEnvelope({'status': 'success'}), isNull);
      expect(currentFromEnvelope({'current': 'x'}), isNull);
    });
  });
}
