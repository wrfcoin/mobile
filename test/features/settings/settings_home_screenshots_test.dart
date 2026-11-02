import 'dart:async';
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
/// test_helpers/screenshot_fonts.dart. Tab content is test fixture data.
void main() {
  const screens = <String, (String, Size, Size)>{
    'settings': ('/profile/settings', Size(390, 2300), Size(1280, 2300)),
    'weather': ('/weather', Size(390, 844), Size(1280, 800)),
    'collect': ('/collect', Size(390, 844), Size(1280, 800)),
    'earnings': ('/wallet', Size(390, 844), Size(1280, 800)),
    'govern': ('/govern', Size(390, 844), Size(1280, 800)),
    'profile': ('/profile', Size(390, 844), Size(1280, 800)),
  };
  for (final screen in screens.entries) {
    final (path, phone, desktop) = screen.value;
    for (final (name, size) in [
      ('phone-390', phone),
      ('desktop-1280', desktop),
    ]) {
      testWidgets('${screen.key} $name', (tester) async {
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
        await tester.pumpWidget(await buildTestApp(db: db));
        await pumpFrames(tester);
        final router = ProviderScope.containerOf(
          tester.element(find.byType(Router<Object>).first),
        ).read(appRouterProvider);
        if (screen.key == 'settings') {
          // As the gear opens it: pushed over the tab the user is on.
          router.go('/weather');
          await pumpFrames(tester);
          unawaited(router.push(path));
        } else {
          router.go(path);
        }
        await pumpFrames(tester, frames: 8);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../docs/screens/settings/${screen.key}-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
