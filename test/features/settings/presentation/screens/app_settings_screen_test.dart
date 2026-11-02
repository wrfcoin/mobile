import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/core/localization/app_localizations.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/app_settings_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';

import '../../../../test_helpers/fakes.dart';

class _NoWallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => null;
}

const _destinations = <String, String>{
  'Sensor settings': '/collect/settings',
  'Weather alerts': '/weather/alert-settings',
  'Payout notifications': '/wallet/notifications',
  'Privacy Center': '/profile/privacy',
  'Calibration certificates': '/collect/calibration',
  'Station security': '/collect/station-security',
  'Transfer or accept a station': '/collect/station-transfer',
  'Collector validation': '/collect/validation',
  'Field mode': '/collect/field-mode',
};

Widget _app({ThemeMode mode = ThemeMode.light}) {
  final router = GoRouter(
    initialLocation: '/profile/settings',
    routes: [
      GoRoute(
        path: '/profile/settings',
        builder: (_, _) => const AppSettingsScreen(),
      ),
      for (final path in _destinations.values)
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('dest:$path')),
        ),
    ],
  );
  return ProviderScope(
    overrides: [
      appPreferencesStoreProvider.overrideWithValue(
        TestAppPreferencesStore(const AppPreferences()),
      ),
      // Wallet unavailable: the settings entries must still be there.
      walletProvider.overrideWith(_NoWallet.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      themeMode: mode,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
    ),
  );
}

void main() {
  for (final entry in _destinations.entries) {
    testWidgets('Settings reaches "${entry.key}" with no station status', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(entry.key), 300);
      await tester.ensureVisible(find.text(entry.key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(find.text('dest:${entry.value}'), findsOneWidget);
    });
  }

  testWidgets('Station submit credential is listed and fails visibly', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Station submit credential'),
      300,
    );
    await tester.ensureVisible(find.text('Station submit credential'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Station submit credential'));
    await tester.pumpAndSettle();
    expect(find.text('This phone station is unavailable.'), findsOneWidget);
  });

  testWidgets('dark theme renders the sections', (tester) async {
    await tester.pumpWidget(_app(mode: ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('Collecting'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Station security'), 300);
    expect(find.text('Station security'), findsOneWidget);
  });

  testWidgets('sections and their entries come in the agreed order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    const expected = [
      'Collecting',
      'Sensor settings',
      'Collector validation',
      'Field mode',
      'Station',
      'Station submit credential',
      'Station security',
      'Transfer or accept a station',
      'Calibration certificates',
      'Alerts & notifications',
      'Weather alerts',
      'Payout notifications',
      'Privacy',
      'Privacy Center',
      'App',
      'Appearance',
      'Data Display',
      'Diagnostics',
      'Replay onboarding tour',
      'About',
    ];
    final tops = [
      for (final label in expected) tester.getTopLeft(find.text(label)).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '"${expected[i]}" should come after "${expected[i - 1]}"',
      );
    }
  });

  testWidgets('existing app settings stay usable and About opens', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Imperial'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imperial'));
    await tester.pumpAndSettle();
    final button = tester.widget<SegmentedButton<UnitSystem>>(
      find.byType(SegmentedButton<UnitSystem>),
    );
    expect(button.selected, {UnitSystem.imperial});

    await tester.ensureVisible(find.text('About'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('WRFCoin'), findsOneWidget);
    expect(find.text('Licensed under MIT OR Apache-2.0.'), findsOneWidget);
  });
}
