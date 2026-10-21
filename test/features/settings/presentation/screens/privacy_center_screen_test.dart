import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wrfcoin_mobile/core/localization/app_localizations.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/privacy_center_screen.dart';

import '../../../../test_helpers/fakes.dart';

void main() {
  testWidgets('privacy center renders consent categories and status', (
    tester,
  ) async {
    final store = TestAppPreferencesStore(
      const AppPreferences(
        consent: ConsentSettings(
          sensorCollection: true,
          preciseLocation: false,
          imageryUpload: true,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appPreferencesStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const PrivacyCenterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sensor readings'), findsOneWidget);
    expect(find.text('Approximate location'), findsOneWidget);
    expect(find.text('Imagery uploads'), findsOneWidget);
    expect(find.text('Status: On'), findsNWidgets(2));
    expect(find.text('Status: Off'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Retention Summary'), 300);
    expect(find.text('Retention Summary'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });
}
