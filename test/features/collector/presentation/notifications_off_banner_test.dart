import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/notifications_off_banner.dart';
import 'package:wrfcoin_mobile/services/background/collection_service.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';

import '../../../test_helpers/fakes.dart';

class _Service extends CollectionServiceController {
  _Service(this.allowed);
  bool? allowed;

  @override
  bool get supported => true;
  @override
  Future<bool> get isRunning async => true;
  @override
  Future<bool?> get notificationsAllowed async => allowed;
  @override
  void Function() listen(
    void Function() onStopped, {
    void Function()? onTick,
  }) => () {};
}

class _Location extends LocationService {
  int settingsOpened = 0;
  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required bool collecting,
  required _Service service,
  _Location? location,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'collector.isCollecting': collecting,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      collectorRepositoryProvider.overrideWithValue(FakeCollectorRepository()),
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
      locationServiceProvider.overrideWithValue(location ?? _Location()),
    ],
  );
  addTearDown(container.dispose);
  container.read(collectorProvider.notifier);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: Column(children: [NotificationsOffBanner()])),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

void main() {
  final banner = find.byKey(const Key('notifications-off-banner'));

  testWidgets('Collect on, notifications off: the banner says so and opens '
      'the app settings', (tester) async {
    final location = _Location();
    await _mount(
      tester,
      collecting: true,
      service: _Service(false),
      location: location,
    );
    expect(banner, findsOneWidget);
    expect(find.text(notificationsOffBannerText), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(location.settingsOpened, 1);
  });

  testWidgets('notifications allowed: no banner', (tester) async {
    await _mount(tester, collecting: true, service: _Service(true));
    expect(banner, findsNothing);
  });

  testWidgets('unknown (no service on this platform): no banner', (
    tester,
  ) async {
    await _mount(tester, collecting: true, service: _Service(null));
    expect(banner, findsNothing);
  });

  testWidgets('Collect off: no banner', (tester) async {
    await _mount(tester, collecting: false, service: _Service(false));
    expect(banner, findsNothing);
  });

  testWidgets('allowed later in the settings: the banner goes on resume', (
    tester,
  ) async {
    final service = _Service(false);
    await _mount(tester, collecting: true, service: service);
    expect(banner, findsOneWidget);
    service.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });
}
