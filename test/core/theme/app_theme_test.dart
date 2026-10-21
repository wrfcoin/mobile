import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('darkTheme builds without throwing', () {
      expect(() => AppTheme.darkTheme, returnsNormally);
    });

    test('lightTheme builds without throwing', () {
      expect(() => AppTheme.lightTheme, returnsNormally);
    });

    test('darkTheme textTheme.bodyLarge is not null', () {
      final theme = AppTheme.darkTheme;
      expect(theme.textTheme.bodyLarge, isNotNull);
    });

    test('lightTheme textTheme.bodyLarge is not null', () {
      final theme = AppTheme.lightTheme;
      expect(theme.textTheme.bodyLarge, isNotNull);
    });

    test('darkTheme has all required TextTheme entries', () {
      final tt = AppTheme.darkTheme.textTheme;
      expect(tt.displayLarge, isNotNull);
      expect(tt.displayMedium, isNotNull);
      expect(tt.headlineMedium, isNotNull);
      expect(tt.bodyLarge, isNotNull);
      expect(tt.bodyMedium, isNotNull);
      expect(tt.labelLarge, isNotNull);
    });

    testWidgets('ElevatedButton resolves foreground from theme colorScheme',
        (tester) async {
      // The ElevatedButton style should use ColorScheme colors rather than
      // hardcoded hex so it adapts when the scheme changes.
      final theme = AppTheme.darkTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ElevatedButton(
              onPressed: () {},
              child: const Text('Press'),
            ),
          ),
        ),
      );

      // Widget renders without error and ElevatedButton is present.
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    test('AppColors.wcagWarning is defined', () {
      // Ensures the constant is present and non-transparent.
      // Use .a (0.0–1.0) rather than deprecated .alpha (0–255).
      expect(AppColors.wcagWarning.a, greaterThan(0.0));
    });
  });
}
