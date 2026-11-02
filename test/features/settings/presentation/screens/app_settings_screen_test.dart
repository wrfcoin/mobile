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
  'Alert settings': '/weather/alert-settings',
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

  testWidgets('dark theme renders the collector and station section', (
    tester,
  ) async {
    await tester.pumpWidget(_app(mode: ThemeMode.dark));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Collector and station'), 300);
    expect(find.text('Collector and station'), findsOneWidget);
  });
}
