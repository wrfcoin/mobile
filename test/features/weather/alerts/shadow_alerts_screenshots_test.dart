import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/weather/alerts/shadow_alerts_controller.dart';
import 'package:wrfcoin_mobile/features/weather/alerts/shadow_alerts_screen.dart';

class PreviewController extends ShadowAlertsController {
  PreviewController() : super((_) async => []) {
    cell = '0.0,36.0';
    events = [
      {
        'shadow': true,
        'cell': cell,
        'hazard': 'rain',
        'status': 'suppressed_by_official',
        'expires': 1800000600000,
        'official': [
          {'url': 'https://meteo.go.ke/'},
        ],
      },
      {
        'shadow': true,
        'cell': cell,
        'hazard': 'wind',
        'status': 'advisory',
        'expires': 1800000600000,
        'official': [],
      },
    ];
  }
  @override
  Future<void> start() async {}
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('populated ${brightness.name} screenshot', (tester) async {
      final fontPath = Platform.environment['ALERT_SCREENSHOT_FONT']!;
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(ByteData.sublistView(File(fontPath).readAsBytesSync())),
        );
      await loader.load();
      final iconPath = File(fontPath).parent.uri
          .resolve('MaterialIcons-Regular.otf')
          .toFilePath();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(ByteData.sublistView(File(iconPath).readAsBytesSync())),
        );
      await icons.load();
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shadowAlertsEnabledProvider.overrideWithValue(true),
            shadowAlertsControllerProvider.overrideWith((ref) {
              final c = PreviewController();
              ref.onDispose(c.dispose);
              return c;
            }),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'Roboto',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff236d63),
                brightness: brightness,
              ),
            ),
            home: const ShadowAlertsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Official warning takes precedence'), findsOneWidget);
      expect(find.text('WRFCoin research advisory'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../../../docs/alerts/screenshots/${brightness.name}.png',
        ),
      );
    }, skip: Platform.environment['ALERT_SCREENSHOT_FONT'] == null);
  }
}
