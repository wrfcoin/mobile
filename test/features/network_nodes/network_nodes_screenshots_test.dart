import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/network_nodes/data/repositories/network_nodes_repository.dart';
import 'package:wrfcoin_mobile/features/network_nodes/presentation/screens/network_nodes_screen.dart';

import '../../test_helpers/screenshot_fonts.dart';
import '../../test_helpers/stub_http_adapter.dart';
import 'network_nodes_fixtures.dart';

/// PR screenshots, rendered only with SCREENSHOT_FONT_DIR set. See
/// test_helpers/screenshot_fonts.dart. Loaded data here is a test fixture.
void main() {
  final states = <String, (int, Object?) Function(RequestOptions)>{
    'loaded': (_) => (200, loadedNodes),
    'empty': (_) => (200, partlyUnavailableNodes),
    'error': (_) => (502, {'success': false}),
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
              networkNodesRepositoryProvider.overrideWithValue(
                NetworkNodesRepository(stubDio(StubHttpAdapter(state.value))),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme,
              home: const NetworkNodesScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../docs/screens/network_nodes/${state.key}-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
