import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/app_harness.dart';

void main() {
  testWidgets('theme and unit preferences persist across restart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'onboarding.completed': true,
      // The Profile tab (settings entry point) is gated behind the
      // achievements flag (#142).
      'ff_enableAchievementsUi': true,
    });

    var db = createTestDatabase();
    await tester.pumpWidget(await buildTestApp(db: db));
    await pumpFrames(tester);

    await tester.tap(find.text('Profile'));
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Settings'));
    await pumpFrames(tester);

    await tester.ensureVisible(find.text('Light'));
    await pumpFrames(tester);
    await tester.tap(find.text('Light'));
    await pumpFrames(tester);
    await tester.ensureVisible(find.text('Imperial'));
    await pumpFrames(tester);
    await tester.tap(find.text('Imperial'));
    await pumpFrames(tester);

    await db.close();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));

    db = createTestDatabase();
    await tester.pumpWidget(await buildTestApp(db: db));
    await tester.pump(const Duration(milliseconds: 400));

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.light);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.unit_system'), 'imperial');
    expect(prefs.getString('app.theme_mode'), 'light');

    await db.close();
  });
}
