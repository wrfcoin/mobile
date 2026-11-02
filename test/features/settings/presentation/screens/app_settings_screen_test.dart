import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/core/localization/app_localizations.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/app_settings_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

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
  'Transfer a station': '/collect/station-transfer',
  'Accept a station': '/collect/station-accept',
  'Recover a station': '/collect/station-recovery',
  'Collector validation': '/collect/validation',
  'Field mode': '/collect/field-mode',
  'Contacts': '/wallet/contacts',
  'Send allowlist': '/wallet/allowlist',
  'Back up recovery phrase': '/wallet/recovery-phrase',
};

Widget _app({
  ThemeMode mode = ThemeMode.light,
  FakeWalletSecureStorage? walletStorage,
  InMemoryKeyValueStorage? keyStorage,
}) {
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
      if (walletStorage != null)
        walletSecureStorageProvider.overrideWithValue(walletStorage),
      if (keyStorage != null)
        keyManagerProvider.overrideWithValue(
          KeyManager(
            biometric: BiometricService(client: FakeLocalAuthClient()),
            storage: keyStorage,
          ),
        ),
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
      'Transfer a station',
      'Accept a station',
      'Calibration certificates',
      'Wallet',
      'Contacts',
      'Send allowlist',
      'Back up recovery phrase',
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

  group('Emergency Wipe', () {
    Finder wipe() => find.text('Emergency Wipe');

    testWidgets('sits last on the page, set apart, below About', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final danger = find.byKey(const Key('settings-danger-area'));
      expect(danger, findsOneWidget);
      expect(find.text('Privacy: danger area'), findsOneWidget);
      expect(
        tester.getTopLeft(danger).dy,
        greaterThan(tester.getBottomLeft(find.text('About')).dy),
      );
      expect(
        tester.getTopLeft(danger).dy,
        greaterThan(tester.getBottomLeft(find.text('Privacy Center')).dy),
      );
    });

    testWidgets('nothing can be erased without typing WIPE', (tester) async {
      tester.view.physicalSize = const Size(1280, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = FakeWalletSecureStorage();
      final keys = InMemoryKeyValueStorage();
      await keys.write(key: 'wrf_private_key', value: 'synthetic');
      await tester.pumpWidget(_app(walletStorage: storage, keyStorage: keys));
      await tester.pumpAndSettle();
      await tester.tap(wipe());
      await tester.pumpAndSettle();

      expect(find.text('Type WIPE to confirm'), findsOneWidget);
      FilledButton wipeNow() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Wipe now'),
      );
      expect(wipeNow().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'WIP');
      await tester.pump();
      expect(wipeNow().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'WIPE');
      await tester.pump();
      expect(wipeNow().onPressed, isNotNull);

      // Cancel erases nothing, even with WIPE typed.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Type WIPE to confirm'), findsNothing);
      expect(find.textContaining('wiped'), findsNothing);
      expect(storage.clearWalletDataCalls, 0);
      expect(await keys.read(key: 'wrf_private_key'), 'synthetic');
    });
  });
}
