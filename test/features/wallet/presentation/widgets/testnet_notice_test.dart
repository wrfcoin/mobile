import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/localization/app_localizations.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/app_settings_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/testnet_notice.dart';

import '../../../../test_helpers/app_harness.dart';
import '../../../../test_helpers/fakes.dart';
import '../../../../test_helpers/screenshot_fonts.dart';

const _notice =
    'This is a test network. It may be reset without notice. Balances and tokens have no monetary value. No migration to mainnet is promised or implied. Please attach no production bridges, exchange listings or irreplaceable assets.';
const _link = 'https://wrfcoin.com/testnet-disclaimer.html';

void main() {
  Future<SharedPreferences> prefs([Map<String, Object> values = const {}]) {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  Future<void> pumpNotice(WidgetTester tester, SharedPreferences store) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(store)],
        child: const MaterialApp(home: Scaffold(body: TestnetNotice())),
      ),
    );
  }

  testWidgets('testnet expectations and canonical URL are visible', (
    tester,
  ) async {
    await pumpNotice(tester, await prefs());
    expect(find.text(_notice), findsOneWidget);
    expect(find.text(_link), findsOneWidget);
  });

  testWidgets('the X closes it, and it stays closed after a restart', (
    tester,
  ) async {
    final store = await prefs();
    await pumpNotice(tester, store);
    await tester.tap(find.byTooltip('Dismiss testnet notice'));
    await tester.pump();
    expect(find.text(_notice), findsNothing);
    expect(store.getBool(TestnetNoticeDismissedNotifier.preferenceKey), isTrue);

    // A new ProviderScope is a new app start over the same stored preference.
    await pumpNotice(tester, store);
    expect(find.text(_notice), findsNothing);
  });

  testWidgets('it shows until it is closed, across restarts', (tester) async {
    final store = await prefs();
    await pumpNotice(tester, store);
    await pumpNotice(tester, store);
    expect(find.text(_notice), findsOneWidget);
  });

  testWidgets('with no readable preference it shows', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: TestnetNotice())),
      ),
    );
    expect(find.text(_notice), findsOneWidget);
  });

  testWidgets('Settings About keeps the notice and link after a dismissal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await prefs({
      TestnetNoticeDismissedNotifier.preferenceKey: true,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(store),
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(const AppPreferences()),
          ),
        ],
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: AppSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_notice), findsNothing);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text(_notice), findsOneWidget);
    expect(find.text(_link), findsOneWidget);
    expect(find.byTooltip('Dismiss testnet notice'), findsNothing);
  });

  test('wallet mounts the notice outside asynchronous wallet states', () {
    final source = File(
      'lib/features/wallet/presentation/screens/wallet_screen.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('bottomNavigationBar: const SafeArea(child: TestnetNotice()),'),
    );
  });

  for (final (name, size) in [
    ('phone-390', const Size(390, 844)),
    ('desktop-1280', const Size(1280, 800)),
  ]) {
    for (final state in ['wallet', 'about']) {
      testWidgets('screenshot $state $name', (tester) async {
        await loadScreenshotFonts();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              const EventChannel(
                'dev.fluttercommunity.plus/connectivity_status',
              ),
              MockStreamHandler.inline(onListen: (_, _) {}),
            );
        SharedPreferences.setMockInitialValues(<String, Object>{});
        tester.view.physicalSize = state == 'about'
            ? Size(size.width, 2900)
            : size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final db = createTestDatabase();
        addTearDown(db.close);
        await tester.pumpWidget(await buildTestApp(db: db, signedIn: true));
        await pumpFrames(tester);
        final router = ProviderScope.containerOf(
          tester.element(find.byType(Router<Object>).first),
        ).read(appRouterProvider);
        if (state == 'about') {
          router.go('/profile/settings');
          await pumpFrames(tester, frames: 8);
          await tester.tap(find.text('About'));
        } else {
          router.go('/wallet');
        }
        await pumpFrames(tester, frames: 8);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../../../docs/screens/testnet_notice/$state-$name.png',
          ),
        );
      }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
    }
  }
}
