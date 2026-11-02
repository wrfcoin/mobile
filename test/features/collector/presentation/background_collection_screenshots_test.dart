// Renders the PR screenshots. Skipped unless SCREENSHOT_FONT_DIR is set,
// because text rendering differs per platform. To regenerate:
//   SCREENSHOT_FONT_DIR=$FLUTTER/bin/cache/artifacts/material_fonts \
//     flutter test --update-goldens \
//     test/features/collector/presentation/background_collection_screenshots_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/collector_validation_screen.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/battery_exemption_dialog.dart';
import 'package:wrfcoin_mobile/services/background/collection_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fakes.dart';
import '../../../test_helpers/screenshot_fonts.dart';

class _Service extends CollectionServiceController {
  @override
  bool get supported => true;
  @override
  Future<bool> get isRunning async => true;
  @override
  Future<bool?> get isBatteryLimited async => true;
  @override
  void Function() listen(
    void Function() onStopped, {
    void Function()? onTick,
  }) => () {};
}

CollectionRun _run(int minutesAgo, String kind, String outcome, {int n = 0}) {
  final at = DateTime(2026, 11, 2, 15, 30).subtract(Duration(minutes: minutesAgo));
  return CollectionRun(
    id: minutesAgo,
    kind: kind,
    outcome: outcome,
    acceptedCount: n,
    startedAt: at,
    finishedAt: at,
  );
}

void main() {
  final fonts = Platform.environment['SCREENSHOT_FONT_DIR'] != null;
  for (final (width, size) in const [
    ('phone-390', Size(390, 1100)),
    ('desktop-1280', Size(1280, 900)),
  ]) {
    Future<ProviderContainer> mount(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadScreenshotFonts);
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'collector.isCollecting': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = FakeCollectorRepository(
        reading: SensorReadingModel(
          latitude: 46.8,
          longitude: -92.1,
          pressureHpa: 1012.4,
          timestamp: DateTime(2026, 11, 2, 15),
        ),
      );
      (repo.db as FakeCollectorLocalStore).collectionRuns = [
        _run(0, 'sync_service', 'success', n: 1),
        _run(0, 'service', 'reading_saved'),
        _run(15, 'job', 'barometer_unavailable'),
        _run(15, 'service', 'not_due'),
        _run(30, 'app_open', 'reading_saved'),
      ];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          collectorRepositoryProvider.overrideWithValue(repo),
          syncWorkerProvider.overrideWithValue(FakeSyncWorker()),
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(
              const AppPreferences(
                consent: ConsentSettings(
                  sensorCollection: true,
                  preciseLocation: true,
                ),
              ),
            ),
          ),
          collectionServiceProvider.overrideWithValue(_Service()),
        ],
      );
      addTearDown(container.dispose);
      container.read(collectorProvider.notifier);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Roboto'),
            home: home,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('battery question $width', skip: !fonts, (tester) async {
      final container = await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => askBatteryExemptionOnce(
                  context,
                  ProviderScope.containerOf(
                    context,
                  ).read(collectorProvider.notifier),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      expect(container.read(collectorProvider).isCollecting, isTrue);
      await tester.tap(find.text('go'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../../../docs/screenshots/background-collection/battery-question-$width.png',
        ),
      );
    });

    testWidgets('run log $width', skip: !fonts, (tester) async {
      await mount(tester, const CollectorValidationScreen());
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../../../docs/screenshots/background-collection/run-log-$width.png',
        ),
      );
    });
  }
}
