import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/alert_settings_screen.dart';

void main() {
  testWidgets('says alerts are delivered only while the app is open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AlertSettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Alerts are delivered while the app is open.'),
      findsOneWidget,
    );
  });
}
