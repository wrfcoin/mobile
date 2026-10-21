import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/onboarding/presentation/providers/welcome_controller.dart';
import 'package:wrfcoin_mobile/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService({required this.grant});

  final bool grant;

  @override
  Future<bool> requestPermission() async => grant;
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: child,
    );
  }
}

Widget _wrap({required Widget child, LocationService? location}) {
  return ProviderScope(
    overrides: [
      if (location != null) locationServiceProvider.overrideWithValue(location),
    ],
    child: _TestApp(child: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FeatureFlags.enableFirstRunWelcome', () {
    test('defaults to false (dark-launched)', () {
      const flags = FeatureFlags();
      expect(flags.enableFirstRunWelcome, isFalse);
    });

    test('copyWith toggles the flag without touching others', () {
      const flags = FeatureFlags(enableOnboardingTour: true);
      final enabled = flags.copyWith(enableFirstRunWelcome: true);
      expect(enabled.enableFirstRunWelcome, isTrue);
      expect(enabled.enableOnboardingTour, isTrue,
          reason: 'copyWith must not clobber unrelated flags');
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

  group('WelcomeScreen slides', () {
    testWidgets('first slide shows earn-loop pitch and Next button',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(child: const WelcomeScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Earn WRF for your local weather data'),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Skip'), findsOneWidget);
    });

    testWidgets('tapping Next advances to the sensor slide',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(child: const WelcomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      expect(find.text("Your phone's barometer is already a sensor"),
          findsOneWidget);
      expect(find.text('Allow approximate location'), findsOneWidget);
    });

    testWidgets('requesting location shows granted state when service grants',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        child: const WelcomeScreen(),
        location: _FakeLocationService(grant: true),
      ));
      await tester.pumpAndSettle();

      // Advance to slide 2.
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Allow approximate location'));
      await tester.pumpAndSettle();

      expect(find.text('Location access granted'), findsOneWidget);
    });

    testWidgets('requesting location shows fallback copy when service denies',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        child: const WelcomeScreen(),
        location: _FakeLocationService(grant: false),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Allow approximate location'));
      await tester.pumpAndSettle();

      expect(find.textContaining('grant later in settings'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);
    });

    testWidgets('final slide shows wallet CTAs and referral field',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(child: const WelcomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      expect(find.text('Create a new wallet'), findsOneWidget);
      expect(find.text('Import an existing wallet'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget,
          reason: 'referral-code TextField should be present on slide 3');
      expect(find.text('Referral code (optional)'), findsOneWidget);
      // Next button is hidden on the last slide.
      expect(find.widgetWithText(FilledButton, 'Next'), findsNothing);
    });
  });

  group('WelcomeController persistence', () {
    test('complete() flips seenWelcome and persists through the store',
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
    });

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
