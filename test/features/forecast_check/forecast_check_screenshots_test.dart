import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/forecast_check/data/repositories/forecast_check_repository.dart';
import 'package:wrfcoin_mobile/features/forecast_check/presentation/screens/forecast_check_screen.dart';

import '../../test_helpers/screenshot_fonts.dart';
import '../../test_helpers/stub_http_adapter.dart';
import 'forecast_check_fixtures.dart';

/// PR screenshots, rendered only with SCREENSHOT_FONT_DIR set. See
/// test_helpers/screenshot_fonts.dart. Loaded data here is a test fixture.
void main() {
  final states = <String, (int, Object?) Function(RequestOptions)>{
    'loaded': (_) => (200, loadedSummary),
    'empty': (_) => (200, emptySummary),
    'error': (_) => (503, {'error': 'x'}),
  };
  for (final (name, size) in screenshotSizes) {
    for (final state in states.entries) {
      testWidgets('${state.key} $name', (tester) async {
        await loadScreenshotFonts();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              forecastCheckRepositoryProvider.overrideWithValue(
                ForecastCheckRepository(stubDio(StubHttpAdapter(state.value))),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme,
              home: const ForecastCheckScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../docs/screens/forecast_check/${state.key}-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
