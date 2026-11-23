import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/current_conditions_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/weather_card.dart';

import '../../../../test_helpers/fakes.dart';

/// The big temperature and Wind come from the latest observation when there
/// is one. The forecast period may be "Tonight" (the overnight low: 4 °C →
/// 39 °F while it is really 9 °C → 48 °F), so it is only a fallback.
void main() {
  const forecast = ForecastModel(
    temperature: 4,
    humidity: 80,
    pressure: 1015,
    windSpeed: 10,
    location: 'San Jose',
    timestamp: '2026-11-23T03:00:00Z',
  );

  Future<void> pump(WidgetTester tester, {CurrentConditions? current}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(
              const AppPreferences(
                unitSystem: UnitSystem.imperial,
                timezonePreference: TimezonePreference.utc,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WeatherCard(forecast: forecast, current: current),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('observation present: observed temperature and wind shown', (
    tester,
  ) async {
    await pump(
      tester,
      current: const CurrentConditions(
        temperatureC: 9,
        relativeHumidityPercent: 62,
        barometricPressureHpa: 1013.25,
        windSpeedKmh: 16,
        observedAt: '2026-11-23T03:50:00Z',
      ),
    );
    expect(find.text('48°F'), findsOneWidget);
    expect(find.text('39°F'), findsNothing);
    expect(find.text('10 mph'), findsOneWidget); // 16 km/h
    expect(find.text('6 mph'), findsNothing); // the forecast's 10 km/h
    expect(tester.takeException(), isNull);
  });

  testWidgets('observation absent: forecast fallback kept', (tester) async {
    await pump(tester);
    expect(find.text('39°F'), findsOneWidget);
    expect(find.text('6 mph'), findsOneWidget);
    expect(find.text(WeatherCard.notAvailable), findsNothing);
  });

  testWidgets('observation without temperature or wind says Not available', (
    tester,
  ) async {
    await pump(
      tester,
      current: const CurrentConditions(
        relativeHumidityPercent: 62,
        barometricPressureHpa: 1013.25,
      ),
    );
    expect(find.text('39°F'), findsNothing);
    expect(find.text('6 mph'), findsNothing);
    expect(find.text('0°F'), findsNothing);
    expect(find.text('32°F'), findsNothing);
    expect(find.text('0 mph'), findsNothing);
    // Temperature, Wind and Updated; humidity and pressure are present.
    expect(find.text(WeatherCard.notAvailable), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a real 0 °C observation is 32°F, not missing', (tester) async {
    await pump(
      tester,
      current: const CurrentConditions(temperatureC: 0, windSpeedKmh: 0),
    );
    expect(find.text('32°F'), findsOneWidget);
    expect(find.text('0 mph'), findsOneWidget);
  });

  group('Updated row', () {
    String updated(WidgetTester tester) {
      final row = find.ancestor(
        of: find.text('Updated'),
        matching: find.byType(Wrap),
      );
      return tester
          .widgetList<Text>(
            find.descendant(of: row.first, matching: find.byType(Text)),
          )
          .map((t) => t.data ?? '')
          .firstWhere((t) => t != 'Updated');
    }

    testWidgets('observation present: its observedAt', (tester) async {
      await pump(
        tester,
        current: const CurrentConditions(
          temperatureC: 9,
          observedAt: '2026-11-23T03:50:00Z',
        ),
      );
      expect(updated(tester), contains('3:50'));
      expect(updated(tester), isNot(contains('3:00')));
    });

    testWidgets('observation absent: the forecast timestamp', (tester) async {
      await pump(tester);
      expect(updated(tester), contains('3:00'));
    });

    testWidgets('observation without observedAt: Not available', (
      tester,
    ) async {
      await pump(tester, current: const CurrentConditions(temperatureC: 9));
      expect(updated(tester), WeatherCard.notAvailable);
    });
  });
}
