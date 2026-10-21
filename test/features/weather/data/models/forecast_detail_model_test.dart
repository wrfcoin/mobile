import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/weather_envelopes.dart';

/// mobile#270: the detail models are parsed from the backend's real forecast
/// envelope (NOAA-NWS periods), not from an invented `/detail` shape.
Map<String, dynamic> _envelope(Object? periods) => {
  'forecast': {'periods': periods},
  'source': 'NOAA-NWS',
};

void main() {
  group('hourlyFromEnvelope', () {
    test('maps NOAA quantities; a null quantity stays null', () {
      final hours = hourlyFromEnvelope(
        _envelope([
          {
            'startTime': '2026-09-28T18:00:00-05:00',
            'temperature': 68,
            'temperatureUnit': 'F',
            'relativeHumidity': {'unitCode': 'wmoUnit:percent', 'value': 62},
            'probabilityOfPrecipitation': {
              'unitCode': 'wmoUnit:percent',
              'value': 20,
            },
            'windSpeed': '10 mph',
            'windDirection': 'NW',
            'shortForecast': 'Mostly Clear',
          },
          {
            'startTime': '2026-09-28T19:00:00-05:00',
            'temperature': 19,
            'temperatureUnit': 'C',
            'relativeHumidity': {'unitCode': 'wmoUnit:percent', 'value': null},
          },
        ]),
      )!;

      expect(hours, hasLength(2));
      expect(hours[0].temperature, closeTo(20, 1e-9));
      expect(hours[0].humidity, 62);
      expect(hours[0].precipitationProbability, closeTo(0.2, 1e-9));
      expect(hours[0].windSpeed, closeTo(16.09344, 1e-9));
      expect(hours[0].windDirection, 'NW');
      expect(hours[0].shortForecast, 'Mostly Clear');

      expect(hours[1].temperature, 19);
      expect(hours[1].humidity, isNull);
      expect(hours[1].precipitationProbability, isNull);
      expect(hours[1].windSpeed, isNull);
    });

    test('not an envelope, or no periods: null (not available)', () {
      expect(hourlyFromEnvelope(null), isNull);
      expect(hourlyFromEnvelope({'error': true}), isNull);
      expect(hourlyFromEnvelope(_envelope(const [])), isNull);
      expect(hourlyFromEnvelope(_envelope('x')), isNull);
    });
  });

  group('dailyFromEnvelope', () {
    Map<String, dynamic> period(String start, bool day, int f) => {
      'startTime': start,
      'isDaytime': day,
      'temperature': f,
      'temperatureUnit': 'F',
      'windSpeed': day ? '10 to 15 mph' : '5 mph',
      'shortForecast': day ? 'Sunny' : 'Clear',
    };

    test('merges day and night periods by the grid date', () {
      final days = dailyFromEnvelope(
        _envelope([
          period('2026-09-28T18:00:00-05:00', false, 58),
          period('2026-09-29T06:00:00-05:00', true, 75),
          period('2026-09-29T18:00:00-05:00', false, 57),
        ]),
      )!;

      expect(days.map((d) => d.date), ['2026-09-28', '2026-09-29']);
      expect(days[0].tempMax, isNull, reason: 'only "Tonight" is left');
      expect(days[0].tempMin, closeTo((58 - 32) * 5 / 9, 1e-9));
      expect(days[0].shortForecast, 'Clear');
      expect(days[1].tempMax, closeTo((75 - 32) * 5 / 9, 1e-9));
      expect(days[1].tempMin, closeTo((57 - 32) * 5 / 9, 1e-9));
      expect(days[1].windSpeed, closeTo(15 * 1.609344, 1e-9));
      expect(days[1].shortForecast, 'Sunny');
      // The daily periods carry none of these: absent, never zero.
      for (final day in days) {
        expect(day.humidityMin, isNull);
        expect(day.humidityMax, isNull);
        expect(day.precipitationProbability, isNull);
      }
    });

    test('at most maxDays days', () {
      final days = dailyFromEnvelope(
        _envelope([
          for (var d = 1; d <= 9; d++)
            period('2026-10-0${d}T06:00:00-05:00', true, 70),
        ]),
      )!;
      expect(days, hasLength(7));
      expect(days.last.date, '2026-10-07');
    });

    test('not an envelope, or no periods: null (not available)', () {
      expect(dailyFromEnvelope(null), isNull);
      expect(dailyFromEnvelope(_envelope(const [])), isNull);
    });
  });
}
