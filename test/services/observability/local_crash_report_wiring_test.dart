import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wrfcoin_mobile/core/localization/app_localizations.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/app_settings_screen.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/widgets/diagnostics_card.dart';
import 'package:wrfcoin_mobile/services/observability/crash_reporter.dart';
import 'package:wrfcoin_mobile/services/observability/crash_report_store.dart';

import '../../test_helpers/fakes.dart';

class TestCrashStore extends MemoryCrashReporter implements CrashReportStore {
  int exports = 0;

  @override
  Future<int> count() async => reports.length;

  @override
  Future<List<XFile>> exportFiles() async {
    exports++;
    return [
      XFile.fromData(Uint8List.fromList([123, 125]), name: 'crash-test.json'),
    ];
  }

  @override
  Future<void> clear() async => reports.clear();
}

void main() {
  test('production reporter forwards to the local store', () async {
    final store = TestCrashStore();
    final c = ProviderContainer(
      overrides: [
        localCrashReportStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(c.dispose);
    await c
        .read(crashReporterProvider)
        .recordError(
          StateError('controlled failure'),
          StackTrace.current,
          reason: 'test',
        );
    expect(store.reports, hasLength(1));
    expect(store.exports, 0);
  });

  testWidgets('real Settings exposes local diagnostics without exporting', (
    tester,
  ) async {
    final store = TestCrashStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localCrashReportStoreProvider.overrideWith((ref) async => store),
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(const AppPreferences()),
          ),
        ],
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const AppSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Diagnostics'), 300);
    await tester.pumpAndSettle();
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('0 crash reports on this device'), findsOneWidget);
    expect(store.exports, 0);
  });

  testWidgets('only an explicit Share exports; Delete clears without sharing', (
    tester,
  ) async {
    final store = TestCrashStore();
    await store.recordError(
      StateError('controlled'),
      StackTrace.current,
      reason: 'test',
    );
    var shares = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localCrashReportStoreProvider.overrideWith((ref) async => store),
          shareCrashReportsProvider.overrideWithValue((files, origin) async {
            shares++;
            expect(files, hasLength(1));
            expect(origin.width, greaterThan(0));
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: DiagnosticsCard())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 crash report on this device'), findsOneWidget);
    expect(store.exports, 0);
    expect(shares, 0);
    await tester.tap(find.text('Share crash reports'));
    await tester.pumpAndSettle();
    expect(store.exports, 1);
    expect(shares, 1);
    await tester.tap(find.text('Delete crash reports'));
    await tester.pumpAndSettle();
    expect(store.reports, isEmpty);
    expect(find.text('0 crash reports on this device'), findsOneWidget);
    expect(store.exports, 1);
    expect(shares, 1);
  });

  testWidgets(
    'unavailable platform has disabled actions, never a fabricated zero',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCrashReportStoreProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: Scaffold(body: DiagnosticsCard())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Local crash reports are unavailable on this platform.'),
        findsOneWidget,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
    },
  );
}
