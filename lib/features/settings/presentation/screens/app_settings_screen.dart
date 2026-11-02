import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../services/crypto/station_signing.dart';
import '../../../collector/presentation/screens/station_submit_token_screen.dart';
import '../../../onboarding/presentation/providers/onboarding_controller.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
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
      body: ResponsiveListView(
        maxContentWidth: 760,
        children: [
          const _SectionHeading('Collecting', first: true),
          _EntryCard(
            children: [
              _entry(
                Icons.sensors,
                'Sensor settings',
                'Choose which sensors collect and how often.',
                () => context.push('/collect/settings'),
              ),
              _entry(
                Icons.fact_check_outlined,
                'Collector validation',
                'Check that your readings pass validation.',
                () => context.push('/collect/validation'),
              ),
              _entry(
                Icons.radar,
                'Field mode',
                'Field diagnostics for your sensors.',
                () => context.push('/collect/field-mode'),
              ),
            ],
          ),
          const _SectionHeading('Station'),
          _EntryCard(
            children: [
              _entry(
                Icons.key,
                'Station submit credential',
                'Import or view the credential your station submits with.',
                () => _openSubmitCredential(context, ref),
              ),
              _entry(
                Icons.security,
                'Station security',
                'Freeze, deactivate or recover your station.',
                () => context.push('/collect/station-security'),
              ),
              _entry(
                Icons.swap_horiz,
                'Transfer or accept a station',
                'Give your station away or accept one.',
                () => context.push('/collect/station-transfer'),
              ),
              _entry(
                Icons.verified_outlined,
                'Calibration certificates',
                "Check any station's signed sensor calibration.",
                () => context.push('/collect/calibration'),
              ),
            ],
          ),
          const _SectionHeading('Alerts & notifications'),
          _EntryCard(
            children: [
              _entry(
                Icons.warning_amber_outlined,
                'Weather alerts',
                'Choose which weather alerts you see.',
                () => context.push('/weather/alert-settings'),
              ),
              _entry(
                Icons.notifications_outlined,
                'Payout notifications',
                'Get a notification when this wallet is paid.',
                () => context.push('/wallet/notifications'),
              ),
            ],
          ),
          const _SectionHeading('Privacy'),
          _EntryCard(
            children: [
              _entry(
                Icons.privacy_tip,
                localizations.privacyCenter,
                localizations.privacySummary,
                () => context.push('/profile/privacy'),
              ),
            ],
          ),
          const _SectionHeading('App'),
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
          _EntryCard(
            children: [
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Replay onboarding tour'),
                subtitle: const Text(
                  'Show the first-run walkthrough again with wallet, collect, and earnings tips.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await ref
                      .read(onboardingControllerProvider.notifier)
                      .restart();
                  if (context.mounted) {
                    context.go('/onboarding');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                subtitle: const Text(
                  'App name, licence and open-source notices.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'WRFCoin',
                  applicationLegalese: 'Licensed under MIT OR Apache-2.0.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openSubmitCredential(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final address = (await ref.read(walletProvider.future))?.address;
      if (address == null) throw StateError('Wallet unavailable.');
      final stationId = deriveMobileStationId(address.trim().toLowerCase());
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => StationSubmitTokenScreen(stationId: stationId),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This phone station is unavailable.')),
      );
    }
  }

  Widget _entry(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title, {this.first = false});

  final String title;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 0 : 24, 4, 8),
      child: Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: children),
      ),
    );
  }
}
