import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/competitions/data/repositories/competition_repository.dart';
import 'package:wrfcoin_mobile/features/competitions/presentation/screens/competitions_screen.dart';

import '../../test_helpers/screenshot_fonts.dart';
import '../../test_helpers/stub_http_adapter.dart';
import 'competition_fixtures.dart';

/// PR screenshots, rendered only with SCREENSHOT_FONT_DIR set. See
/// test_helpers/screenshot_fonts.dart. Loaded data here is a test fixture.
void main() {
  (int, Object?) routed(RequestOptions o, Object list, Object current) =>
      o.path == '/competitions' ? (200, list) : (200, current);
  final states = <String, (int, Object?) Function(RequestOptions)>{
    'loaded': (o) => routed(o, loadedWeeks, loadedCurrent),
    'empty': (o) => routed(o, emptyWeeks, emptyCurrent),
    'error': (_) => (500, {'error': 'x'}),
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
              competitionRepositoryProvider.overrideWithValue(
                CompetitionRepository(stubDio(StubHttpAdapter(state.value))),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme,
              home: const CompetitionsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../docs/screens/competitions/${state.key}-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
