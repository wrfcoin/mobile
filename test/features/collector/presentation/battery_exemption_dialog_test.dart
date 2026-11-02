// The battery question: asked once, declinable, and never again.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/battery_exemption_dialog.dart';
import 'package:wrfcoin_mobile/services/background/collection_service.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';

import '../../../test_helpers/fakes.dart';

class _Service extends CollectionServiceController {
  bool? limited = true;
  int requests = 0;
  @override
  Future<bool> get isRunning async => true;
  @override
  Future<bool?> get isBatteryLimited async => limited;
  @override
  Future<void> requestBatteryExemption() async => requests++;
  @override
  void Function() listen(void Function() onStopped) => () {};
}

class _Location extends LocationService {}

void main() {
  late _Service service;

  Future<CollectorNotifier> mount(
    WidgetTester tester, {
    bool collecting = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'collector.isCollecting': collecting,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        collectorRepositoryProvider.overrideWithValue(
          FakeCollectorRepository(
            reading: SensorReadingModel(
              latitude: 1,
              longitude: 2,
              pressureHpa: 1000,
              timestamp: DateTime.utc(2026, 11, 2),
            ),
          ),
        ),
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
        collectionServiceProvider.overrideWithValue(service),
        locationServiceProvider.overrideWithValue(_Location()),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(collectorProvider.notifier);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => askBatteryExemptionOnce(context, notifier),
            child: const Text('go'),
          ),
        ),
      ),
    );
    // Let the provider's restore finish, outside the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    return notifier;
  }

  Future<void> ask(WidgetTester tester) async {
    await tester.tap(find.text('go'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => service = _Service());

  testWidgets('declining sends nothing and is final', (tester) async {
    await mount(tester);
    await ask(tester);
    expect(find.text('Keep collecting while the phone sleeps?'), findsOneWidget);
    expect(find.textContaining('uses more battery'), findsOneWidget);
    await tester.tap(find.text('No thanks'));
    await tester.pumpAndSettle();
    expect(service.requests, 0);

    await ask(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('accepting opens the system dialog, once', (tester) async {
    await mount(tester);
    await ask(tester);
    await tester.tap(find.text('Continue'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(service.requests, 1);

    await ask(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.requests, 1);
  });

  testWidgets('dismissing counts as an answer', (tester) async {
    await mount(tester);
    await ask(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(service.requests, 0);
    await ask(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('already exempt: never asked', (tester) async {
    service.limited = false;
    await mount(tester);
    await ask(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('unknown or unsupported: never asked', (tester) async {
    service.limited = null;
    await mount(tester);
    await ask(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('collection off: never asked', (tester) async {
    await mount(tester, collecting: false);
    await ask(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('the first-time explanation', () {
    Future<bool?> explain(WidgetTester tester, {required String tap}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await explainBackgroundCollectionOnce(
                  context,
                  const CollectorPreferences(),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('your rough location'), findsOneWidget);
      expect(find.textContaining('never your exact position'), findsOneWidget);
      expect(find.textContaining('permanent notification'), findsOneWidget);
      await tester.tap(find.text(tap));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('declining leaves it off, and it shows again', (tester) async {
      expect(await explain(tester, tap: 'Not now'), isFalse);
      expect(
        await const CollectorPreferences().backgroundCollectionExplained(),
        isFalse,
      );
    });

    testWidgets('accepting is remembered', (tester) async {
      expect(await explain(tester, tap: 'Turn on'), isTrue);
      expect(
        await const CollectorPreferences().backgroundCollectionExplained(),
        isTrue,
      );
    });
  });
}
