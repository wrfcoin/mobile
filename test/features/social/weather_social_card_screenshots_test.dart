import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/social/weather_social_card.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';

// Renders with SCREENSHOT_FONTS set to a folder holding Roboto-Regular.ttf
// and MaterialIcons-Regular.otf:
// flutter test --update-goldens test/features/social/weather_social_card_screenshots_test.dart
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

  testWidgets('phone screenshot', (tester) async {
    await load('Roboto', 'Roboto-Regular.ttf');
    await load('MaterialIcons', 'MaterialIcons-Regular.otf');
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme.copyWith(
          textTheme: AppTheme.darkTheme.textTheme.apply(fontFamily: 'Roboto'),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
            child: WeatherSocialCard(
              forecast: const ForecastModel(
                temperature: 4,
                windSpeed: 16.09344, // NOAA "10 mph"
                windDirection: 'NW',
                location: 'Your area',
                timestamp: '2026-11-23T02:00:00Z',
              ),
              weatherRewards: '12.34',
              shareService: WeatherSocialCardShareService(
                captureCard: (_) async => Uint8List(0),
                shareLauncher: (_, {text}) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('16 km/h NW'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../../docs/screenshots/social-weather-card/forecast-phone.png',
      ),
    );
  }, skip: fonts == null);
}
