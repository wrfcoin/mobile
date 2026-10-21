import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../collector/presentation/providers/collector_provider.dart';

class PrivacyCenterScreen extends ConsumerStatefulWidget {
  const PrivacyCenterScreen({super.key});

  @override
  ConsumerState<PrivacyCenterScreen> createState() =>
      _PrivacyCenterScreenState();
}

class _PrivacyCenterScreenState extends ConsumerState<PrivacyCenterScreen> {
  static const _privacyPolicyUrl = 'https://wrfcoin.com/privacy';
  static const _termsUrl = 'https://wrfcoin.com/terms';

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final preferences = ref.watch(appPreferencesProvider).preferences;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.privacyCenter)),
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
                    localizations.consentTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(localizations.consentSummary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ConsentTile(
            icon: Icons.sensors,
            title: localizations.sensorConsent,
            description: localizations.sensorConsentDescription,
            value: preferences.consent.sensorCollection,
            statusLabel: preferences.consent.sensorCollection
                ? localizations.statusOn
                : localizations.statusOff,
            onChanged: (value) => _setConsent(ConsentType.sensor, value),
          ),
          const SizedBox(height: 12),
          _ConsentTile(
            icon: Icons.location_on,
            title: localizations.locationConsent,
            description: localizations.locationConsentDescription,
            value: preferences.consent.preciseLocation,
            statusLabel: preferences.consent.preciseLocation
                ? localizations.statusOn
                : localizations.statusOff,
            onChanged: (value) => _setConsent(ConsentType.location, value),
          ),
          const SizedBox(height: 12),
          _ConsentTile(
            icon: Icons.image,
            title: localizations.imageryConsent,
            description: localizations.imageryConsentDescription,
            value: preferences.consent.imageryUpload,
            statusLabel: preferences.consent.imageryUpload
                ? localizations.statusOn
                : localizations.statusOff,
            onChanged: (value) => _setConsent(ConsentType.imagery, value),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(localizations.requiredForCollecting),
              subtitle: Text(
                preferences.consent.canCollect
                    ? localizations.collectionEnabled
                    : localizations.collectionBlocked,
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
                    localizations.retentionTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(localizations.retentionBody),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_user),
                  title: Text(localizations.privacyPolicy),
                  subtitle: const Text(_privacyPolicyUrl),
                  trailing: const Icon(Icons.copy),
                  onTap: () => _copyLink(context, _privacyPolicyUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(localizations.termsOfService),
                  subtitle: const Text(_termsUrl),
                  trailing: const Icon(Icons.copy),
                  onTap: () => _copyLink(context, _termsUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _revokeAllConsent(context),
            icon: const Icon(Icons.block),
            label: Text(localizations.revokeConsent),
          ),
        ],
      ),
    );
  }

  Future<void> _setConsent(ConsentType type, bool value) async {
    final localizations = AppLocalizations.of(context);
    final notifier = ref.read(appPreferencesProvider.notifier);

    if (value) {
      await notifier.setConsent(type, true);
      return;
    }

    final shouldRevoke = await showConfirmDialog(
      context,
      title: localizations.revokeConsentTitle,
      message: localizations.revokeConsentBody,
      confirmLabel: localizations.revoke,
      cancelLabel: localizations.stay,
    );
    if (!shouldRevoke) return;

    await notifier.setConsent(type, false);
    if (type == ConsentType.sensor || type == ConsentType.location) {
      await ref.read(collectorProvider.notifier).handleConsentRevoked();
      if (!mounted) return;
      AppSnackbars.success(
        context,
        localizations.consentRevoked,
        detail: localizations.consentRevokedDetail,
      );
    }
  }

  Future<void> _revokeAllConsent(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    final shouldRevoke = await showConfirmDialog(
      context,
      title: localizations.revokeConsentTitle,
      message: localizations.revokeConsentBody,
      confirmLabel: localizations.revoke,
      cancelLabel: localizations.stay,
    );
    if (!shouldRevoke) return;

    await ref
        .read(appPreferencesProvider.notifier)
        .revokeAllCollectionConsent();
    await ref.read(collectorProvider.notifier).handleConsentRevoked();
    if (!context.mounted) return;
    AppSnackbars.success(
      context,
      localizations.consentRevoked,
      detail: localizations.consentRevokedDetail,
    );
  }

  void _copyLink(BuildContext context, String link) {
    final localizations = AppLocalizations.of(context);
    Clipboard.setData(ClipboardData(text: link));
    AppSnackbars.success(context, localizations.copiedLink, detail: link);
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.statusLabel,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final String statusLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            const SizedBox(height: 4),
            Text(
              'Status: $statusLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
