import 'dart:io';

import 'package:fpdart/fpdart.dart' show Either, Left;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/time/app_clock.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_provider.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/fakes.dart';
import '../../test_helpers/screenshot_fonts.dart';

class _Weather extends FakeWeatherRepository {
  bool down = false;

  @override
  Future<Either<Failure, ForecastModel>> getForecast(CoarseLocation location) {
    if (down) return Future.value(const Left(ServerFailure('down')));
    return super.getForecast(location);
  }
}

/// PR screenshots, rendered only with SCREENSHOT_FONT_DIR set. See
/// test_helpers/screenshot_fonts.dart. Tab content is test fixture data.
void main() {
  for (final (name, size) in const [
    ('phone-390', Size(390, 844)),
    ('desktop-1280', Size(1280, 800)),
  ]) {
    for (final failed in const [false, true]) {
      final state = failed ? 'refresh-failed' : 'fresh';
      testWidgets('weather $state $name', (tester) async {
        await loadScreenshotFonts();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              const EventChannel(
                'dev.fluttercommunity.plus/connectivity_status',
              ),
              MockStreamHandler.inline(onListen: (_, _) {}),
            );
        SharedPreferences.setMockInitialValues(<String, Object>{});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final AppDatabase db = createTestDatabase();
        addTearDown(db.close);

        var now = DateTime(2026, 11, 1, 12);
        final weather = _Weather();
        final location = CoarseLocation.round(45, -93);
        await tester.pumpWidget(
          await buildTestApp(
            db: db,
            weatherRepository: weather,
            weatherLocationResolver: FixedWeatherLocationResolver(location),
            extraOverrides: [appClockProvider.overrideWithValue(() => now)],
          ),
        );
        await pumpFrames(tester);

        if (failed) {
          await tester.runAsync(
            () => db.deleteOfflineData(
              'weather:forecast:${location.pathSegment}',
            ),
          );
          now = now.add(const Duration(minutes: 25));
          weather.down = true;
          final container = ProviderScope.containerOf(
            tester.element(find.byType(Router<Object>).first),
          );
          await container.read(weatherProvider.notifier).refreshIfStale();
          await pumpFrames(tester);
        }
        await pumpFrames(tester, frames: 8);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../docs/screens/weather-tab/$state-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
