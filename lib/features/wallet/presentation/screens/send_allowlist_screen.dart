import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../data/models/address_book_entry.dart';
import '../../domain/send_allowlist.dart';
import '../providers/wallet_security_provider.dart';
import '../widgets/safety_notice.dart';

/// App-level send allowlist: Send only goes to contacts you allowed.
class SendAllowlistScreen extends ConsumerWidget {
  const SendAllowlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(sendAllowlistProvider);
    final policy = ref.watch(sendAllowlistPolicyProvider);
    final entries = ref.watch(addressBookProvider).value ?? const [];
    final settings = settingsAsync.value ?? SendAllowlistSettings.off;
    final on = policy.isOn(settings);
    final turnsOffAt = on ? settings.turnsOffAt : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Send allowlist')),
      body: ResponsiveCenter(
        child: ListView(
          children: [
            Card(
              child: SwitchListTile(
                key: const Key('allowlist-switch'),
                title: const Text('Only send to allowed contacts'),
                subtitle: Text(
                  !on
                      ? 'Off. Send works with any address.'
                      : turnsOffAt == null
                      ? 'On. Send refuses everyone else.'
                      : 'On until ${formatAllowlistTime(turnsOffAt)}.',
                ),
                value: on && turnsOffAt == null,
                onChanged: settingsAsync.isLoading
                    ? null
                    : (value) => value
                          ? ref.read(sendAllowlistProvider.notifier).turnOn()
                          : _confirmTurnOff(context, ref),
              ),
            ),
            if (turnsOffAt != null) ...[
              const SizedBox(height: 8),
              SafetyNotice(
                key: const Key('allowlist-turn-off-pending'),
                tone: SafetyTone.caution,
                icon: Icons.schedule,
                title: 'Turning off at ${formatAllowlistTime(turnsOffAt)}',
                body:
                    'Until then, Send still only goes to allowed contacts. '
                    'If someone asked you to turn this off, keep it on.',
                children: [
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    key: const Key('allowlist-keep-on'),
                    onPressed: () => ref
                        .read(sendAllowlistProvider.notifier)
                        .cancelTurnOff(),
                    child: const Text('Keep it on'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const SafetyNotice(
              title: 'How it works',
              body:
                  'Turning this on is instant. Turning it off, or allowing a '
                  'new contact while it is on, waits 24 hours. That gives you '
                  'time to notice a mistake or a scam. It uses this phone\'s '
                  'clock.',
            ),
            const SizedBox(height: 8),
            Text(
              sendAllowlistScopeNote,
              key: const Key('allowlist-scope-note'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Contacts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/wallet/contacts'),
                  icon: const Icon(Icons.contacts_outlined, size: 18),
                  label: const Text('Manage'),
                ),
              ],
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Add contacts first, then allow the ones you send to.',
                ),
              ),
            for (final entry in entries)
              _AllowTile(
                entry: entry,
                state: policy.stateOf(entry),
                onAllow: () => _confirmAllow(context, ref, entry, on),
                onRevoke: () => ref
                    .read(addressBookProvider.notifier)
                    .revoke(entry.address),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTurnOff(BuildContext context, WidgetRef ref) async {
    final at = ref
        .read(sendAllowlistPolicyProvider)
        .now
        .add(sendAllowlistCooldown);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off the allowlist?'),
        content: Text(
          'It stays on for 24 hours, until ${formatAllowlistTime(at)}. You '
          'can keep it on any time before then.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it on'),
          ),
          TextButton(
            key: const Key('allowlist-turn-off-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn off in 24 hours'),
          ),
        ],
      ),
    );
    if (sure == true) {
      await ref.read(sendAllowlistProvider.notifier).requestTurnOff();
    }
  }

  Future<void> _confirmAllow(
    BuildContext context,
    WidgetRef ref,
    AddressBookEntry entry,
    bool on,
  ) async {
    final at = ref
        .read(sendAllowlistPolicyProvider)
        .now
        .add(sendAllowlistCooldown);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Allow "${entry.label}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              entry.address,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              on
                  ? 'You can send to this address from '
                        '${formatAllowlistTime(at)} (in 24 hours).'
                  : 'You can send to this address when the allowlist is on.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Only allow an address you checked yourself. Nobody from '
              'WRFCoin will ever ask you to allow one.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('allowlist-allow-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(on ? 'Allow in 24 hours' : 'Allow'),
          ),
        ],
      ),
    );
    if (sure == true) {
      await ref.read(addressBookProvider.notifier).allow(entry.address);
    }
  }
}

class _AllowTile extends StatelessWidget {
  const _AllowTile({
    required this.entry,
    required this.state,
    required this.onAllow,
    required this.onRevoke,
  });

  final AddressBookEntry entry;
  final ContactAllowState state;
  final VoidCallback onAllow;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final (String status, Widget action) = switch (state) {
      ContactAllowState.allowed => (
        'Allowed',
        TextButton(onPressed: onRevoke, child: const Text('Remove')),
      ),
      ContactAllowState.pending => (
        'Allowed from ${formatAllowlistTime(entry.allowedFrom!)}',
        TextButton(onPressed: onRevoke, child: const Text('Cancel')),
      ),
      ContactAllowState.notAllowed => (
        'Not allowed',
        OutlinedButton(
          key: Key('allow-${entry.address.toLowerCase()}'),
          onPressed: onAllow,
          child: const Text('Allow'),
        ),
      ),
    };
    return Card(
      child: ListTile(
        leading: Icon(switch (state) {
          ContactAllowState.allowed => Icons.verified_user_outlined,
          ContactAllowState.pending => Icons.schedule,
          ContactAllowState.notAllowed => Icons.person_outline,
        }),
        title: Text(entry.label),
        subtitle: Text(
          '$status\n${entry.address}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: action,
      ),
    );
  }
}
