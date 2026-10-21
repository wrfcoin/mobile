import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_detail_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/weather_envelopes.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/weather_card.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/forecast_detail_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_detail_screen.dart';

/// mobile#335 (backend#1307): daily periods carry
/// `relativeHumidity: {min,max}|null`; hourly periods carry a plain percent
/// or null (the deployed backend still sends `{unitCode,value}` until its
/// next deploy). Null is absent, never 0; a real 0 is 0%.

Map<String, dynamic> _envelope(List<Map<String, dynamic>> periods) => {
  'forecast': {'periods': periods},
};

Map<String, dynamic> _day(
  String start,
  bool day, {
  Object? rh,
  bool has = true,
}) => {
  'startTime': start,
  'isDaytime': day,
  'temperature': 60,
  'temperatureUnit': 'F',
  if (has) 'relativeHumidity': rh,
};

Map<String, dynamic> _hour(String start, {Object? rh, bool has = true}) => {
  'startTime': start,
  'temperature': 60,
  'temperatureUnit': 'F',
  if (has) 'relativeHumidity': rh,
};

DailyForecast _oneDay({Object? rh, bool has = true}) => dailyFromEnvelope(
  _envelope([_day('2026-10-01T06:00:00-05:00', true, rh: rh, has: has)]),
)!.single;

double? _oneHour({Object? rh, bool has = true}) => hourlyFromEnvelope(
  _envelope([_hour('2026-10-01T06:00:00-05:00', rh: rh, has: has)]),
)!.single.humidity;

void main() {
  group('daily relativeHumidity {min,max}', () {
    test('range', () {
      final d = _oneDay(rh: {'min': 45, 'max': 80});
      expect(d.humidityMin, 45);
      expect(d.humidityMax, 80);
    });
    test('equal min/max', () {
      final d = _oneDay(rh: {'min': 60, 'max': 60});
      expect(d.humidityMin, 60);
      expect(d.humidityMax, 60);
    });
    test('real 0 is kept, not treated as absent', () {
      final d = _oneDay(rh: {'min': 0, 'max': 0});
      expect(d.humidityMin, 0);
      expect(d.humidityMax, 0);
    });
    test('null is absent', () {
      final d = _oneDay(rh: null);
      expect(d.humidityMin, isNull);
      expect(d.humidityMax, isNull);
    });
    test('missing field is absent', () {
      final d = _oneDay(has: false);
      expect(d.humidityMin, isNull);
      expect(d.humidityMax, isNull);
    });
    test('day and night periods merge to the widest range', () {
      final d = dailyFromEnvelope(
        _envelope([
          _day('2026-10-01T06:00:00-05:00', true, rh: {'min': 45, 'max': 70}),
          _day('2026-10-01T18:00:00-05:00', false, rh: {'min': 60, 'max': 80}),
        ]),
      )!.single;
      expect(d.humidityMin, 45);
      expect(d.humidityMax, 80);
    });
    test('night null, day present: day range only', () {
      final d = dailyFromEnvelope(
        _envelope([
          _day('2026-10-01T06:00:00-05:00', true, rh: {'min': 45, 'max': 70}),
          _day('2026-10-01T18:00:00-05:00', false, rh: null),
        ]),
      )!.single;
      expect(d.humidityMin, 45);
      expect(d.humidityMax, 70);
    });
    test('malformed object is absent', () {
      expect(_oneDay(rh: {'min': 'x', 'max': 5}).humidityMin, isNull);
      expect(_oneDay(rh: 'wet').humidityMax, isNull);
    });
  });

  group('hourly relativeHumidity', () {
    test('new shape: plain percent', () => expect(_oneHour(rh: 62), 62));
    test('real 0 is 0', () => expect(_oneHour(rh: 0), 0));
    test('null is absent', () => expect(_oneHour(rh: null), isNull));
    test('missing field is absent', () => expect(_oneHour(has: false), isNull));
    test(
      'old shape {unitCode,value} reads .value',
      () => expect(
        _oneHour(rh: {'unitCode': 'wmoUnit:percent', 'value': 62}),
        62,
      ),
    );
    test(
      'old shape with null value is absent',
      () => expect(
        _oneHour(rh: {'unitCode': 'wmoUnit:percent', 'value': null}),
        isNull,
      ),
    );
  });

  group('forecastFromEnvelope humidity (current-conditions fallback)', () {
    double? parse({Object? rh, bool has = true}) => forecastFromEnvelope(
      _envelope([_hour('2026-10-01T06:00:00-05:00', rh: rh, has: has)]),
    )!.humidity;

    test('plain percent', () => expect(parse(rh: 62), 62));
    test(
      'old {unitCode,value} shape',
      () => expect(parse(rh: {'unitCode': 'wmoUnit:percent', 'value': 62}), 62),
    );
    test('null', () => expect(parse(rh: null), isNull));
    test('missing', () => expect(parse(has: false), isNull));
    test('a real 0 stays 0', () => expect(parse(rh: 0), 0));

    testWidgets('WeatherCard shows 62% from the forecast when /current is '
        'not loaded', (tester) async {
      final forecast = forecastFromEnvelope(
        _envelope([_hour('2026-10-01T06:00:00-05:00', rh: 62)]),
      )!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appPreferencesProvider.overrideWith(_PrefsNotifier.new)],
          child: MaterialApp(
            home: Scaffold(body: WeatherCard(forecast: forecast)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('62%'), findsOneWidget);
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, ForecastDetail detail) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forecastDetailProvider.overrideWith(
              () => _FixedDetailNotifier(detail),
            ),
            appPreferencesProvider.overrideWith(_PrefsNotifier.new),
          ],
          child: const MaterialApp(home: ForecastDetailScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    DailyForecast day(String date, {int? min, int? max}) =>
        DailyForecast(date: date, humidityMin: min, humidityMax: max);

    testWidgets('7-day: range, single value, real 0, and hidden when null', (
      tester,
    ) async {
      await pump(
        tester,
        ForecastDetail(
          hourly: const [],
          daily: [
            day('2026-10-01', min: 45, max: 80),
            day('2026-10-02', min: 60, max: 60),
            day('2026-10-03', min: 0, max: 0),
            day('2026-10-04'),
          ],
        ),
      );
      await tester.tap(find.text('7-Day'));
      await tester.pumpAndSettle();

      expect(find.text('Humidity 45\u201380%'), findsOneWidget);
      expect(find.text('Humidity 60%'), findsOneWidget);
      expect(find.text('Humidity 0%'), findsOneWidget);
      // The fourth day has no humidity: the row is hidden, not "—" or 0.
      expect(find.textContaining('Humidity'), findsNWidgets(3));
      expect(find.textContaining('Pressure'), findsNothing);
    });

    testWidgets('hourly: NN% when present, absent when null, no pressure', (
      tester,
    ) async {
      await pump(
        tester,
        const ForecastDetail(
          hourly: [
            HourlyForecast(
              timestamp: '2026-10-01T06:00:00-05:00',
              humidity: 62,
            ),
            HourlyForecast(timestamp: '2026-10-01T07:00:00-05:00', humidity: 0),
            HourlyForecast(timestamp: '2026-10-01T08:00:00-05:00'),
          ],
          daily: [],
        ),
      );

      expect(find.textContaining('Humidity 62%'), findsOneWidget);
      expect(find.textContaining('Humidity 0%'), findsOneWidget);
      expect(find.textContaining('Humidity \u2014'), findsOneWidget);
      expect(find.textContaining('Pressure'), findsNothing);
    });
  });
}

class _FixedDetailNotifier extends ForecastDetailNotifier {
  _FixedDetailNotifier(this._detail);
  final ForecastDetail _detail;

  @override
  ForecastDetailState build() => ForecastDetailState(detail: _detail);

  @override
  Future<void> loadLocal() async {}
}

class _PrefsNotifier extends AppPreferencesNotifier {
  @override
  AppPreferencesState build() => const AppPreferencesState();
}
