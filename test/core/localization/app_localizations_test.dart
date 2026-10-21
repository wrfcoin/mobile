import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/localization/app_localizations.dart';

void main() {
  group('AppLocalizations', () {
    testWidgets('English strings render correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return Scaffold(
                body: Center(
                  child: Text(l10n.settings),
                ),
              );
            },
          ),
        ),
      );

      // Use pump + 100ms instead of pumpAndSettle per memory
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Ajustes'), findsNothing);
    });

    testWidgets('Spanish locale overrides English', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return Scaffold(
                body: Center(
                  child: Text(l10n.settings),
                ),
              );
            },
          ),
        ),
      );

      // Use pump + 100ms instead of pumpAndSettle per memory
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('Multiple keys render correctly in Spanish', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return Scaffold(
                body: Column(
                  children: [
                    Text(l10n.privacyCenter),
                    Text(l10n.consentTitle),
                    Text(l10n.revokeConsent),
                  ],
                ),
              );
            },
          ),
        ),
      );

      // Use pump + 100ms instead of pumpAndSettle per memory
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Centro de privacidad'), findsOneWidget);
      expect(find.text('Consentimiento de recopilacion'), findsOneWidget);
      expect(find.text('Revocar todo el consentimiento'), findsOneWidget);
    });

    testWidgets('Fallback to English for unsupported locale', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'), // Unsupported locale
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return Scaffold(
                body: Center(
                  child: Text(l10n.settings),
                ),
              );
            },
          ),
        ),
      );

      // Use pump + 100ms instead of pumpAndSettle per memory
      await tester.pump(const Duration(milliseconds: 100));

      // Should fallback to English when locale is not supported
      expect(find.text('Settings'), findsOneWidget);
    });

    test('AppLocalizations properly initializes with English locale', () {
      final l10n = AppLocalizations(const Locale('en'));
      expect(l10n.settings, 'Settings');
      expect(l10n.appearance, 'Appearance');
      expect(l10n.privacyCenter, 'Privacy Center');
    });

    test('AppLocalizations properly initializes with Spanish locale', () {
      final l10n = AppLocalizations(const Locale('es'));
      expect(l10n.settings, 'Ajustes');
      expect(l10n.appearance, 'Apariencia');
      expect(l10n.privacyCenter, 'Centro de privacidad');
    });

    test('AppLocalizations has correct supported locales', () {
      expect(AppLocalizations.supportedLocales.length, 2);
      expect(AppLocalizations.supportedLocales, contains(const Locale('en')));
      expect(AppLocalizations.supportedLocales, contains(const Locale('es')));
    });
  });
}
