// "Your Weather Story" lives on the Profile tab now, and its detail still opens.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/weather_narrative.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/weather_stories_screen.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/screenshot_fonts.dart';

const _title = 'Your Weather Story';

class _Stories extends WeatherNarrativesNotifier {
  _Stories(this.narratives);

  final List<WeatherNarrative> narratives;

  @override
  WeatherNarrativesState build() =>
      WeatherNarrativesState(narratives: narratives);
}

final _story = WeatherNarrative(
  type: NarrativeType.values.first,
  title: 'Warmest reading yet',
  description: 'Your station read its highest temperature so far.',
  date: DateTime(2026, 10, 30),
  icon: Icons.thermostat,
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async => db.close());

  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    List<WeatherNarrative>? stories,
    Size size = const Size(390, 2000),
    bool realFonts = true,
  }) async {
    if (realFonts) await loadFlutterCacheFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
        weatherNarratives: () => _Stories(stories ?? [_story]),
      ),
    );
    await pumpFrames(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>).first),
    ).read(appRouterProvider);
  }

  testWidgets('the story is on Profile and no longer on Weather', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    expect(find.text(_title), findsNothing);
    expect(find.text('Warmest reading yet'), findsNothing);

    router.go('/profile');
    await pumpFrames(tester);
    expect(find.text(_title), findsOneWidget);
    expect(find.text('Warmest reading yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('See all opens the stories and Back returns to Profile', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.go('/profile');
    await pumpFrames(tester);

    await tester.tap(find.text('See all'));
    await pumpUntilFound(tester, find.byType(WeatherStoriesScreen));
    await pumpFrames(tester);

    await tester.tap(find.byType(BackButton));
    await pumpFrames(tester);
    expect(find.byType(WeatherStoriesScreen), findsNothing);
    expect(find.text(_title), findsOneWidget);
    expect(router.state.uri.path, '/profile');
  });

  testWidgets('with no stories Profile shows no empty card', (tester) async {
    final router = await pumpApp(tester, stories: const []);
    router.go('/profile');
    await pumpFrames(tester);
    expect(find.text(_title), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the deep link to the stories still resolves', (tester) async {
    final router = await pumpApp(tester);
    router.go('/weather/stories');
    await pumpUntilFound(tester, find.byType(WeatherStoriesScreen));
    expect(router.state.uri.path, '/weather/stories');
  });

  for (final (name, size) in const [
    ('phone-390', Size(390, 844)),
    ('desktop-1280', Size(1280, 800)),
  ]) {
    testWidgets('screenshot $name', (tester) async {
      await loadScreenshotFonts();
      final router = await pumpApp(tester, size: size, realFonts: false);
      router.go('/profile');
      await pumpFrames(tester, frames: 8);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screens/weather-story/$name.png'),
      );
    }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
  }
}
