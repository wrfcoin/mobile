import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../onboarding/presentation/providers/onboarding_controller.dart';
import '../widgets/diagnostics_card.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final preferencesState = ref.watch(appPreferencesProvider);
    final preferences = preferencesState.preferences;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.appearance,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(localizations.themeMode),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(localizations.themeSystem),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(localizations.themeLight),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(localizations.themeDark),
                      ),
                    ],
                    selected: {preferences.themeMode},
                    onSelectionChanged: (selection) {
                      ref
                          .read(appPreferencesProvider.notifier)
                          .setThemeMode(selection.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.dataDisplay,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(localizations.unitSystem),
                  const SizedBox(height: 8),
                  SegmentedButton<UnitSystem>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: UnitSystem.metric,
                        label: Text(localizations.unitsMetric),
                      ),
                      ButtonSegment(
                        value: UnitSystem.imperial,
                        label: Text(localizations.unitsImperial),
                      ),
                    ],
                    selected: {preferences.unitSystem},
                    onSelectionChanged: (selection) {
                      ref
                          .read(appPreferencesProvider.notifier)
                          .setUnitSystem(selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(localizations.language),
                  const SizedBox(height: 8),
                  SegmentedButton<AppLocaleOption>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: AppLocaleOption.system,
                        label: Text(localizations.languageSystem),
                      ),
                      ButtonSegment(
                        value: AppLocaleOption.english,
                        label: Text(localizations.languageEnglish),
                      ),
                      ButtonSegment(
                        value: AppLocaleOption.spanish,
                        label: Text(localizations.languageSpanish),
                      ),
                    ],
                    selected: {preferences.localeOption},
                    onSelectionChanged: (selection) {
                      ref
                          .read(appPreferencesProvider.notifier)
                          .setLocaleOption(selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(localizations.timezone),
                  const SizedBox(height: 8),
                  SegmentedButton<TimezonePreference>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: TimezonePreference.deviceLocal,
                        label: Text(localizations.timezoneDevice),
                      ),
                      ButtonSegment(
                        value: TimezonePreference.utc,
                        label: Text(localizations.timezoneUtc),
                      ),
                    ],
                    selected: {preferences.timezonePreference},
                    onSelectionChanged: (selection) {
                      ref
                          .read(appPreferencesProvider.notifier)
                          .setTimezonePreference(selection.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const DiagnosticsCard(),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const Icon(Icons.privacy_tip),
              title: Text(localizations.privacyCenter),
              subtitle: Text(localizations.privacySummary),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/privacy'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Replay onboarding tour'),
              subtitle: const Text(
                'Show the first-run walkthrough again with wallet, collect, and earnings tips.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await ref.read(onboardingControllerProvider.notifier).restart();
                if (context.mounted) {
                  context.go('/onboarding');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
