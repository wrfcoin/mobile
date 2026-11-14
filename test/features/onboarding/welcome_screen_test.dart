import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/features/onboarding/presentation/providers/welcome_controller.dart';
import 'package:wrfcoin_mobile/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';

import '../../test_helpers/fakes.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService({required this.grant});

  final bool grant;

  @override
  Future<bool> requestPermission() async => grant;
}

class _Barometer extends SensorDataSource {
  _Barometer(this.has) : super(LocationService());
  final bool? has;
  @override
  Future<bool?> hasBarometer() async => has;
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: child);
  }
}

Widget _wrap({
  required Widget child,
  LocationService? location,
  bool? barometer,
}) {
  return ProviderScope(
    overrides: [
      if (location != null) locationServiceProvider.overrideWithValue(location),
      sensorDataSourceProvider.overrideWithValue(_Barometer(barometer)),
    ],
    child: _TestApp(child: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FeatureFlags.enableFirstRunWelcome', () {
    test('is on by default', () {
      const flags = FeatureFlags();
      expect(flags.enableFirstRunWelcome, isTrue);
    });

    test('copyWith toggles the flag without touching others', () {
      const flags = FeatureFlags(enableOnboardingTour: true);
      final enabled = flags.copyWith(enableFirstRunWelcome: false);
      expect(enabled.enableFirstRunWelcome, isFalse);
      expect(
        enabled.enableOnboardingTour,
        isTrue,
        reason: 'copyWith must not clobber unrelated flags',
      );
    });
  });

  group('WelcomeState.shouldShowWelcome', () {
    test('false until controller has loaded', () {
      const state = WelcomeState();
      expect(state.shouldShowWelcome, isFalse);
    });

    test('true when loaded and never seen', () {
      const state = WelcomeState(loaded: true, seenWelcome: false);
      expect(state.shouldShowWelcome, isTrue);
    });

    test('false when loaded and already seen', () {
      const state = WelcomeState(loaded: true, seenWelcome: true);
      expect(state.shouldShowWelcome, isFalse);
    });
  });

  group('a phone without a barometer', () {
    testWidgets('is not promised earning by itself, and is pointed at a '
        'station on the web', (tester) async {
      await tester.pumpWidget(
        _wrap(child: const WelcomeScreen(), barometer: false),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcome-no-barometer')), findsOneWidget);
      expect(
        find.text('Earn test WRF for your local weather data'),
        findsNothing,
      );
      expect(find.textContaining('no barometer'), findsOneWidget);
      expect(find.textContaining('wrfcoin.com'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      expect(find.text('This phone has no barometer'), findsOneWidget);
      expect(
        find.text("Your phone's barometer is already a sensor"),
        findsNothing,
      );
      expect(find.text('Allow sensors and location'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining('collects and earns here'), findsNothing);
      expect(find.textContaining('Collecting on this phone'), findsNothing);
    });

    for (final has in const [true, null]) {
      testWidgets('a barometer ($has) keeps the usual slides', (tester) async {
        await tester.pumpWidget(
          _wrap(child: const WelcomeScreen(), barometer: has),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Earn test WRF for your local weather data'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('welcome-no-barometer')), findsNothing);
      });
    }
  });

  group('WelcomeScreen slides', () {
    testWidgets('first slide shows earn-loop pitch and Next button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(child: const WelcomeScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Earn test WRF for your local weather data'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Skip'), findsOneWidget);
    });

    testWidgets('tapping Next advances to the sensor slide', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(child: const WelcomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      expect(
        find.text("Your phone's barometer is already a sensor"),
        findsOneWidget,
      );
      expect(find.text('Allow sensors and location'), findsOneWidget);
    });

    testWidgets('requesting location shows granted state when service grants', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          child: const WelcomeScreen(),
          location: _FakeLocationService(grant: true),
        ),
      );
      await tester.pumpAndSettle();

      // Advance to slide 2.
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Allow sensors and location'));
      await tester.pumpAndSettle();

      expect(find.text('Location access granted'), findsOneWidget);
    });

    testWidgets('requesting location shows fallback copy when service denies', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          child: const WelcomeScreen(),
          location: _FakeLocationService(grant: false),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Allow sensors and location'));
      await tester.pumpAndSettle();

      expect(find.textContaining('grant later in settings'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);
    });

    testWidgets('final slide offers the wallet choices and asks for nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(child: const WelcomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      expect(find.text('Create a 12-word wallet'), findsOneWidget);
      expect(find.text('Use a passkey'), findsOneWidget);
      expect(find.text('I already have a 12-word wallet'), findsOneWidget);
      expect(
        find.textContaining('No sign-up, email or phone number'),
        findsOneWidget,
      );
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'first run asks for no personal data',
      );
      // Next button is hidden on the last slide.
      expect(find.widgetWithText(FilledButton, 'Next'), findsNothing);
    });

    testWidgets('a yes to location records the consent Collect needs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          child: const WelcomeScreen(),
          location: _FakeLocationService(grant: true),
        ),
      );
      await tester.pumpAndSettle();
      // The app has its preferences loaded long before this screen shows.
      ProviderScope.containerOf(tester.element(find.byType(WelcomeScreen)))
          .read(appPreferencesProvider);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow sensors and location'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WelcomeScreen)),
      );
      expect(
        container.read(appPreferencesProvider).preferences.consent.canCollect,
        isTrue,
      );
    });

    testWidgets('a no to location records no consent', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          child: const WelcomeScreen(),
          location: _FakeLocationService(grant: false),
        ),
      );
      await tester.pumpAndSettle();
      // The app has its preferences loaded long before this screen shows.
      ProviderScope.containerOf(tester.element(find.byType(WelcomeScreen)))
          .read(appPreferencesProvider);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow sensors and location'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WelcomeScreen)),
      );
      expect(
        container.read(appPreferencesProvider).preferences.consent.canCollect,
        isFalse,
      );
    });
  });

  group('WelcomeController persistence', () {
    test('a phone that already has a wallet is past first run', () async {
      final storage = InMemoryKeyValueStorage();
      await storage.write(key: 'wrf_address', value: '0xabc');
      await storage.write(key: 'wrf_private_key', value: '0xkey');
      final container = ProviderContainer(
        overrides: [
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: storage,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(welcomeControllerProvider.notifier).load();
      expect(
        container.read(welcomeControllerProvider).shouldShowWelcome,
        isFalse,
      );
    });

    test(
      'complete() flips seenWelcome and persists through the store',
      () async {
        const store = WelcomeStore();
        final container = ProviderContainer(
          overrides: [welcomeStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        final controller = container.read(welcomeControllerProvider.notifier);
        await controller.load();
        expect(container.read(welcomeControllerProvider).seenWelcome, isFalse);

        await controller.complete();
        expect(container.read(welcomeControllerProvider).seenWelcome, isTrue);
        // Store has the persisted flag now.
        expect(await store.loadSeen(), isTrue);
      },
    );

    test('reset() re-arms the welcome flow', () async {
      const store = WelcomeStore();
      final container = ProviderContainer(
        overrides: [welcomeStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final controller = container.read(welcomeControllerProvider.notifier);
      await controller.load();
      await controller.complete();
      expect(container.read(welcomeControllerProvider).seenWelcome, isTrue);

      await controller.reset();
      expect(container.read(welcomeControllerProvider).seenWelcome, isFalse);
      expect(await store.loadSeen(), isFalse);
    });
  });
}
