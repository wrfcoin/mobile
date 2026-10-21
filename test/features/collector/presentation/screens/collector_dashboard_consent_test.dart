import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_helpers/app_harness.dart';

void main() {
  testWidgets('collection toggle stays disabled until consent is granted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'onboarding.completed': true,
    });
    final db = createTestDatabase();

    await tester.pumpWidget(await buildTestApp(db: db));
    await pumpFrames(tester);

    await tester.tap(find.text('Collect'));
    await pumpFrames(tester);

    final toggle = tester.widget<Switch>(find.byType(Switch));
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
