import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/privacy_center_screen.dart';

import '../test_helpers/app_harness.dart';

void main() {
  testWidgets('revoking consent disables collection actions', (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'onboarding.completed': true,
      'privacy.sensor_collection': true,
      'privacy.location_collection': true,
      'privacy.imagery_upload': true,
    });

    final db = createTestDatabase();
    await tester.pumpWidget(await buildTestApp(db: db));
    await pumpFrames(tester);

    await tester.tap(find.text('Collect'));
    await pumpFrames(tester);

    var toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.onChanged, isNotNull);

    await tester.tap(find.byTooltip('Settings'));
    await pumpUntilFound(tester, find.text('Collecting'));
    await pumpFrames(tester);
    await tester.ensureVisible(find.text('Privacy Center'));
    await pumpFrames(tester);
    await tester.tap(find.text('Privacy Center'));
    await pumpUntilFound(tester, find.byType(PrivacyCenterScreen));
    await pumpFrames(tester);

    await tester.scrollUntilVisible(
      find.text('Revoke All Collection Consent'),
      300,
    );
    await tester.tap(find.text('Revoke All Collection Consent'));
    await pumpFrames(tester);
    await tester.tap(find.text('Revoke'));
    await pumpFrames(tester);

    await tester.tap(find.text('Collect'));
    await pumpFrames(tester);

    toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.onChanged, isNull);
    expect(
      find.text(
        'Grant sensor and location consent in Privacy Center to enable collection.',
      ),
      findsOneWidget,
    );

    await db.close();
  });
}
