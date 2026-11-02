import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/screenshot_fonts.dart';

/// PR screenshots, rendered only with SCREENSHOT_FONT_DIR set. See
/// test_helpers/screenshot_fonts.dart.
void main() {
  const shots = <String, String>{'weather': '/weather', 'collect': '/collect'};
  for (final shot in shots.entries) {
    for (final (name, size) in const [
      ('phone-390', Size(390, 844)),
      ('desktop-1280', Size(1280, 800)),
    ]) {
      testWidgets('${shot.key} $name', (tester) async {
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
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final AppDatabase db = createTestDatabase();
        addTearDown(db.close);
        await tester.pumpWidget(await buildTestApp(db: db));
        await pumpFrames(tester);
        ProviderScope.containerOf(
          tester.element(find.byType(Router<Object>).first),
        ).read(appRouterProvider).go(shot.value);
        await pumpFrames(tester, frames: 8);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../docs/screens/large_text/${shot.key}-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
