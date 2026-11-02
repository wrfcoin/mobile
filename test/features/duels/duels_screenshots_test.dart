import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/duels/data/models/duel_model.dart';
import 'package:wrfcoin_mobile/features/duels/presentation/providers/duels_provider.dart';
import 'package:wrfcoin_mobile/features/duels/presentation/screens/forecast_duel_screen.dart';
import 'package:wrfcoin_mobile/features/duels/presentation/screens/forecast_duels_screen.dart';
import 'package:fpdart/fpdart.dart';

import 'duel_fixtures.dart';

// Renders with SCREENSHOT_FONTS set to Flutter's bin/cache/artifacts/material_fonts:
// flutter test --update-goldens test/features/duels/duels_screenshots_test.dart
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

  const widths = {'phone': Size(390, 1500), 'desktop': Size(1280, 1300)};
  for (final MapEntry(key: name, value: size) in widths.entries) {
    testWidgets('$name screenshots', (tester) async {
      await load('Roboto', 'Roboto-Regular.ttf');
      await load('MaterialIcons', 'MaterialIcons-Regular.otf');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final board = DuelBoard.fromJson({
        'open': [openDuelJson()],
        'live': [],
        'finished': [finishedDuelJson()],
      });
      Widget app(Widget home) => ProviderScope(
        key: UniqueKey(),
        overrides: [
          duelWalletProvider.overrideWith((ref) async => duelWalletB),
          duelBoardProvider.overrideWith((ref) async => Right(board)),
          duelProvider(
            duelIdForTest,
          ).overrideWith((ref) async => Right(Duel.fromJson(liveDuelJson()))),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme.copyWith(
            textTheme: AppTheme.darkTheme.textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'Roboto'),
            child: home,
          ),
        ),
      );
      await tester.pumpWidget(app(const ForecastDuelsScreen()));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../../docs/screenshots/forecast-duels/board-$name.png',
        ),
      );
      await tester.pumpWidget(app(const ForecastDuelScreen(id: duelIdForTest)));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../../docs/screenshots/forecast-duels/duel-$name.png',
        ),
      );
    }, skip: fonts == null);
  }
}
