import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';

import '../../test_helpers/screenshot_fonts.dart';

class _Barometer extends SensorDataSource {
  _Barometer(this.has) : super(LocationService());
  final bool? has;
  @override
  Future<bool?> hasBarometer() async => has;
}

/// PR screenshots, rendered only with SCREENSHOT_FONT_DIR set.
void main() {
  for (final (name, size) in const [
    ('phone-390', Size(390, 844)),
    ('desktop-1280', Size(1280, 800)),
  ]) {
    for (final (slide, noBarometer) in const [
      (0, false),
      (1, false),
      (2, false),
      (0, true),
      (1, true),
      (2, true),
    ]) {
      final file = noBarometer
          ? 'slide-$slide-no-barometer-$name'
          : 'slide-$slide-$name';
      testWidgets(file, (tester) async {
        await loadScreenshotFonts();
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sensorDataSourceProvider.overrideWithValue(
                _Barometer(noBarometer ? false : null),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme.copyWith(
                textTheme: AppTheme.lightTheme.textTheme.apply(
                  fontFamily: 'Roboto',
                ),
              ),
              home: const WelcomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < slide; i++) {
          await tester.tap(find.widgetWithText(FilledButton, 'Next'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../../../docs/screens/first_run/$file.png'),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
