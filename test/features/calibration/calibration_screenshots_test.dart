import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/calibration/data/station_calibration.dart';
import 'package:wrfcoin_mobile/features/calibration/presentation/station_calibration_screen.dart';

import 'calibration_fixtures.dart';

// Renders with SCREENSHOT_FONTS set to Flutter's bin/cache/artifacts/material_fonts:
// flutter test --update-goldens test/features/calibration/calibration_screenshots_test.dart
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

  const widths = {'phone': Size(390, 900), 'desktop': Size(1280, 800)};
  for (final MapEntry(key: name, value: size) in widths.entries) {
    testWidgets('$name screenshot', (tester) async {
      await load('Roboto', 'Roboto-Regular.ttf');
      await load('MaterialIcons', 'MaterialIcons-Regular.otf');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            phoneStationIdProvider.overrideWith((ref) async => 'phone-station'),
            stationCalibrationProvider('phone-station').overrideWith(
              (ref) async =>
                  Right(StationCalibration.fromJson(calibratedJson())),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme.copyWith(
              textTheme: AppTheme.darkTheme.textTheme.apply(
                fontFamily: 'Roboto',
              ),
            ),
            home: const StationCalibrationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../../docs/screenshots/calibration/lookup-$name.png',
        ),
      );
    }, skip: fonts == null);
  }
}
