import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/weather_card.dart';

import '../../../../test_helpers/fakes.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  const forecast = ForecastModel(
    temperature: 20,
    humidity: 55,
    pressure: 1013.25,
    windSpeed: 18,
    precipitation: 4,
    location: 'San Francisco',
    timestamp: '2026-03-10T13:30:00Z',
  );

  Future<void> pumpSubject(
    WidgetTester tester, {
    required AppPreferences preferences,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(preferences),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeatherCard(forecast: forecast)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('weather card switches temperature and pressure units', (
    tester,
  ) async {
    await pumpSubject(
      tester,
      preferences: const AppPreferences(unitSystem: UnitSystem.metric),
    );
    expect(find.text('20°C'), findsOneWidget);
    expect(find.text('1013 hPa'), findsOneWidget);

    await pumpSubject(
      tester,
      preferences: const AppPreferences(unitSystem: UnitSystem.imperial),
    );
    expect(find.text('68°F'), findsOneWidget);
    expect(find.text('29.92 inHg'), findsOneWidget);
  });

  testWidgets(
    'weather card formats timestamps in selected locale and timezone',
    (tester) async {
      await pumpSubject(
        tester,
        preferences: const AppPreferences(
          localeOption: AppLocaleOption.spanish,
          timezonePreference: TimezonePreference.utc,
        ),
      );

      final updatedFinder = find.textContaining('UTC');
      expect(updatedFinder, findsOneWidget);

      final updatedText = tester.widget<Text>(updatedFinder).data ?? '';
      expect(updatedText.toLowerCase(), contains('mar'));
    },
  );
}
