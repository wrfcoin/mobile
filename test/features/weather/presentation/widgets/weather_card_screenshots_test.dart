import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/current_conditions_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/weather_card.dart';

import '../../../../test_helpers/fakes.dart';

// Renders with SCREENSHOT_FONTS set to a folder holding Roboto-Regular.ttf
// and MaterialIcons-Regular.otf:
// flutter test --update-goldens test/features/weather/presentation/widgets/weather_card_screenshots_test.dart
// The data is a synthetic fixture.
void main() {
  final fonts = Platform.environment['SCREENSHOT_FONTS'];

  Future<void> load(String family, String file) async {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(
          ByteData.sublistView(File('$fonts/$file').readAsBytesSync()),
        ),
      );
    await loader.load();
  }

  const forecast = ForecastModel(
    temperature: 4,
    humidity: 80,
    pressure: 1015,
    windSpeed: 10,
    location: 'San Jose',
    timestamp: '2026-11-23T03:00:00Z',
  );
  const cases = {
    'observed': CurrentConditions(
      temperatureC: 9,
      relativeHumidityPercent: 62,
      barometricPressureHpa: 1013.25,
      windSpeedKmh: 16,
      observedAt: '2026-11-23T03:50:00Z',
    ),
    'observed-missing': CurrentConditions(
      relativeHumidityPercent: 62,
      barometricPressureHpa: 1013.25,
    ),
  };
  const widths = {'phone': Size(390, 420), 'desktop': Size(1280, 420)};
  for (final MapEntry(key: name, value: size) in widths.entries) {
    for (final MapEntry(key: label, value: current) in cases.entries) {
      testWidgets('$name $label screenshot', (tester) async {
        await load('Roboto', 'Roboto-Regular.ttf');
        await load('MaterialIcons', 'MaterialIcons-Regular.otf');
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appPreferencesStoreProvider.overrideWithValue(
                TestAppPreferencesStore(
                  const AppPreferences(unitSystem: UnitSystem.imperial),
                ),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme.copyWith(
                textTheme: AppTheme.darkTheme.textTheme.apply(
                  fontFamily: 'Roboto',
                ),
              ),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: WeatherCard(forecast: forecast, current: current),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../../../docs/screenshots/weather-card/$label-$name.png',
          ),
        );
      }, skip: fonts == null);
    }
  }
}
