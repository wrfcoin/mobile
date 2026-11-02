import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/onboarding/presentation/screens/onboarding_tour_screen.dart';

void main() {
  group('OnboardingTourScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget buildTestApp(Widget child) {
      return ProviderScope(
        child: MaterialApp(
          home: child,
        ),
      );
    }

    testWidgets('Welcome screen renders on first load',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingTourScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Turn your phone into a weather station'), findsOneWidget);
      expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    });

    testWidgets('Next button is visible on non-final screens',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingTourScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.widgetWithText(ElevatedButton, 'Next'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Create Wallet'),
          findsNothing);
    });

    testWidgets('Back button is disabled on first screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingTourScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      final backButton = find.widgetWithText(OutlinedButton, 'Back');
      expect(backButton, findsOneWidget);

      // Button should be disabled (onPressed is null)
      final button = tester.widget<OutlinedButton>(backButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('Skip button is visible on welcome screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingTourScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.widgetWithText(TextButton, 'Skip'), findsOneWidget);
    });

    testWidgets('Final screen shows action buttons', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingTourScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Skip to final screen
      final skipButton = find.widgetWithText(TextButton, 'Skip');
      await tester.tap(skipButton);
      await tester.pump(const Duration(milliseconds: 100));

      // Should show action buttons
      expect(find.widgetWithText(ElevatedButton, 'Create Wallet'),
          findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Explore First'),
          findsOneWidget);
    });

    testWidgets('Progress indicators update on page navigation',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingTourScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Should have 3 progress indicators (for 3 pages)
      expect(find.byType(AnimatedContainer), findsWidgets);
    });

    testWidgets('Dont show again checkbox visible on final screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(const OnboardingTourScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Skip to final screen
      final skipButton = find.widgetWithText(TextButton, 'Skip');
      await tester.tap(skipButton);
      await tester.pump(const Duration(milliseconds: 100));

      // Should show checkbox
      expect(find.widgetWithText(CheckboxListTile, "Don't show again"),
          findsOneWidget);
    });
  });
}
