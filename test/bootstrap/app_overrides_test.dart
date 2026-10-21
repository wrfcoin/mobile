import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/app.dart';
import 'package:wrfcoin_mobile/bootstrap/app_overrides.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/services/observability/crash_reporter.dart';

/// Boots the shipped app with the production container factory (#317/#319).
///
/// Unlike the widget tests built on `test/test_helpers/app_harness.dart`, no
/// harness-only override is added here: the only substitution is the
/// in-memory database executor in place of the on-disk file. A provider that
/// throws unless overridden and is reachable from the app shell fails this
/// test instead of rendering a gray ErrorWidget on a phone.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    // A platform answer, not a provider override: the Weather tab asks
    // Geolocator whether location is granted, and a phone always replies.
    // Here it replies "denied" (0), so the tab makes no request.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => call.method == 'checkPermission' ? 0 : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          null,
        );
  });

  testWidgets(
    'WrfcoinApp builds its first frames with the production container',
    (tester) async {
      final container = await createAppContainer(
        openDatabase: NativeDatabase.memory,
      );
      final database = container.read(appDatabaseProvider);
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const WrfcoinApp(),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);

      // The providers the root router depends on resolve without throwing.
      expect(() => container.read(sharedPreferencesProvider), returnsNormally);
      expect(() => container.read(featureFlagsProvider), returnsNormally);
      expect(() => container.read(appRouterProvider), returnsNormally);
      expect(() => container.read(appDatabaseProvider), returnsNormally);

      // Unmount the tree; tearDown disposes its container and memory database.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  test('preferences failure is crash-reported before being rethrown', () async {
    final reporter = MemoryCrashReporter();
    final failure = PlatformException(code: 'synthetic_preferences_failure');
    var databaseOpened = false;
    await expectLater(
      createAppContainer(
        loadPreferences: () async => throw failure,
        openDatabase: () {
          databaseOpened = true;
          return NativeDatabase.memory();
        },
        bootstrapReporter: reporter,
      ),
      throwsA(same(failure)),
    );
    expect(databaseOpened, isFalse);
    expect(reporter.reports, hasLength(1));
    expect(reporter.reports.single.error, same(failure));
    expect(reporter.reports.single.reason, 'app_bootstrap');
    expect(reporter.reports.single.fatal, isTrue);
  });

  test('database bootstrap failure is also recorded', () async {
    final reporter = MemoryCrashReporter();
    final failure = StateError('synthetic_database_failure');
    await expectLater(
      createAppContainer(
        openDatabase: () => throw failure,
        bootstrapReporter: reporter,
      ),
      throwsA(same(failure)),
    );
    expect(reporter.reports.single.error, same(failure));
    expect(reporter.reports.single.fatal, isTrue);
  });
}
