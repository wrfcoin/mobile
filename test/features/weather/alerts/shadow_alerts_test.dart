import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/weather/alerts/shadow_alerts_controller.dart';
import 'package:wrfcoin_mobile/features/weather/alerts/shadow_alerts_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('disabled feature never constructs a polling controller', (
    tester,
  ) async {
    var constructed = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shadowAlertsEnabledProvider.overrideWithValue(false),
          shadowAlertsControllerProvider.overrideWith((ref) {
            constructed = true;
            return ShadowAlertsController((_) async => []);
          }),
        ],
        child: const MaterialApp(home: ShadowAlertsScreen()),
      ),
    );
    expect(constructed, false);
    expect(find.text('Research alerts are disabled.'), findsOneWidget);
  });
  testWidgets(
    'polling stops in background, cancels pending response, resumes once',
    (tester) async {
      var calls = 0;
      final pending = Completer<List<Map<String, dynamic>>>();
      CancelToken? request;
      final c = ShadowAlertsController((token) {
        calls++;
        request = token;
        return pending.future;
      }, interval: const Duration(seconds: 1));
      c.cell = '0.0,36.0';
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(calls, 1);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(request!.isCancelled, true);
      pending.complete([
        {'id': 'late'},
      ]);
      await tester.pump(const Duration(seconds: 3));
      expect(calls, 1);
      expect(c.events, isEmpty);
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(calls, 2);
      c.dispose();
      await tester.pump(const Duration(seconds: 3));
      expect(calls, 2);
    },
  );
  testWidgets('no overlapping polls and invalid cell never polls', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<List<Map<String, dynamic>>>();
    final c = ShadowAlertsController((_) {
      calls++;
      return pending.future;
    });
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(calls, 0);
    c.cell = '0.0,36.0';
    unawaited(c.poll());
    unawaited(c.poll());
    expect(calls, 1);
    pending.complete([]);
    await tester.pump();
    c.dispose();
  });
  testWidgets('subscription persists only coarse area and hazards', (
    tester,
  ) async {
    final c = ShadowAlertsController((_) async => []);
    await tester.runAsync(() => c.save('0.0,36.0', {'rain'}));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shadow_alerts.cell'), '0.0,36.0');
    expect(prefs.getStringList('shadow_alerts.hazards'), ['rain']);
    await expectLater(c.save('0.001,36.002', {'rain'}), throwsFormatException);
    c.dispose();
  });
  testWidgets('filters stale events and keeps official precedence', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final c = ShadowAlertsController(
      (_) async => [
        {
          'shadow': true,
          'cell': '0.0,36.0',
          'hazard': 'rain',
          'at': now - 1,
          'expires': now + 60000,
          'status': 'suppressed_by_official',
        },
        {
          'shadow': true,
          'cell': '0.0,36.0',
          'hazard': 'rain',
          'at': now - 10,
          'expires': now - 1,
          'status': 'advisory',
        },
      ],
    );
    c.cell = '0.0,36.0';
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(c.events.length, 1);
    expect(c.events.single['status'], 'suppressed_by_official');
    c.dispose();
  });
}
