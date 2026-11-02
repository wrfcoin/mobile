import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/models/address_book_entry.dart';
import '../../domain/address_book_transfer.dart';
import '../../domain/recipient_safety.dart';
import '../../domain/send_allowlist.dart';
import '../providers/wallet_security_provider.dart';
import '../widgets/safety_notice.dart';

/// Opens and shares contacts files. Overridden in tests.
class ContactsFileGateway {
  const ContactsFileGateway();

  /// The text of a file the user picks, or null if they cancel.
  Future<String?> pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Contacts',
          extensions: ['json'],
          mimeTypes: ['application/json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
    return file?.readAsString();
  }

  /// Hands [json] to the system share sheet as a .json file.
  Future<void> share(String json) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'wrfcoin-contacts.json'));
    await file.writeAsString(json, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'WRFCoin contacts',
      ),
    );
  }
}

final contactsFileGatewayProvider = Provider<ContactsFileGateway>(
  (ref) => const ContactsFileGateway(),
);

/// Named contacts ("Send to Mom"). Saved on this phone only.
class AddressBookScreen extends ConsumerWidget {
  const AddressBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(addressBookProvider);
    final policy = ref.watch(sendAllowlistPolicyProvider);
    final entries = book.value ?? const <AddressBookEntry>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          PopupMenuButton<String>(
            key: const Key('contacts-menu'),
            onSelected: (value) => value == 'import'
                ? _import(context, ref)
                : _export(context, ref, entries),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Import from file')),
              PopupMenuItem(value: 'export', child: Text('Export to file')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('contacts-add'),
        onPressed: () => _editContact(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add contact'),
      ),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const SafetyNotice(
              title: 'Saved on this phone only',
              body:
                  'Contacts never leave this phone unless you export them. '
                  'WRFCoin never sees them.',
              icon: Icons.phone_android,
            ),
            const SizedBox(height: 12),
            if (book.isLoading && entries.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'No contacts yet. Add one here, or tick "Save recipient" '
                  'when you send.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final entry in entries)
                _ContactTile(
                  entry: entry,
                  allowState: policy.stateOf(entry),
                  onTap: () => _editContact(context, ref, existing: entry),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    List<AddressBookEntry> entries,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (entries.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('There are no contacts to export.')),
      );
      return;
    }
    try {
      await ref
          .read(contactsFileGatewayProvider)
          .share(exportAddressBook(entries));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Export did not finish. Try again.')),
      );
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final String? raw;
    try {
      raw = await ref.read(contactsFileGatewayProvider).pickFile();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That file could not be opened.')),
      );
      return;
    }
    if (raw == null) return;
    final existing = await ref.read(addressBookProvider.future);
    final alias = await ref.read(keyManagerProvider).getOwnLegacyAlias();
    final result = importAddressBook(
      raw,
      existing: existing,
      ownLegacyAlias: alias,
    );
    if (result.error == null && result.added.isNotEmpty) {
      await ref.read(addressBookProvider.notifier).addAll(result.added);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.error == null && result.added.isNotEmpty
              ? '${result.summary}. Imported contacts are not allowed for '
                    'sending until you allow them.'
              : result.summary,
        ),
      ),
    );
  }

  Future<void> _editContact(
    BuildContext context,
    WidgetRef ref, {
    AddressBookEntry? existing,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ContactDialog(existing: existing),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null ? 'Contact saved' : 'Contact updated'),
        ),
      );
    }
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.entry,
    required this.allowState,
    required this.onTap,
  });

  final AddressBookEntry entry;
  final ContactAllowState allowState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = switch (allowState) {
      ContactAllowState.allowed => const Chip(
        avatar: Icon(Icons.verified_user_outlined, size: 16),
        label: Text('Allowed'),
        visualDensity: VisualDensity.compact,
      ),
      ContactAllowState.pending => Chip(
        avatar: const Icon(Icons.schedule, size: 16),
        label: Text('From ${formatAllowlistTime(entry.allowedFrom!)}'),
        visualDensity: VisualDensity.compact,
      ),
      ContactAllowState.notAllowed => null,
    };
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(entry.label.characters.first.toUpperCase()),
        ),
        title: Text(entry.label),
        subtitle: Text(
          entry.address,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        trailing: chip,
        onTap: onTap,
      ),
    );
  }
}

/// Add a contact, or rename / remove one. The address of a saved contact
/// cannot be edited: a new address is a new contact (and is not allowed).
class _ContactDialog extends ConsumerStatefulWidget {
  const _ContactDialog({this.existing});

  final AddressBookEntry? existing;

  @override
  ConsumerState<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends ConsumerState<_ContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.label);
  late final _address = TextEditingController(text: widget.existing?.address);
  String? _ownLegacyAlias;

  @override
  void initState() {
    super.initState();
    ref.read(keyManagerProvider).getOwnLegacyAlias().then((alias) {
      if (mounted) setState(() => _ownLegacyAlias = alias);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  String? _validateAddress(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Address required';
    if (!isSendableAddress(v)) return 'Must be a 0x... address';
    if (widget.existing != null) return null;
    final book = ref.read(addressBookProvider).value ?? const [];
    for (final e in book) {
      if (e.address.toLowerCase() == v.toLowerCase()) {
        return 'Already saved as "${e.label}"';
      }
    }
    final assessment = assessRecipient(
      to: v,
      addressBook: book,
      ownLegacyAlias: _ownLegacyAlias,
    );
    return assessment.blocksSend ? assessment.reason : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(addressBookProvider.notifier);
    final existing = widget.existing;
    if (existing == null) {
      await notifier.addEntry(
        AddressBookEntry(
          label: _name.text.trim(),
          address: _address.text.trim(),
        ),
      );
    } else {
      await notifier.rename(existing.address, _name.text);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _remove() async {
    final existing = widget.existing!;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove "${existing.label}"?'),
        content: const Text(
          'If you add this address again later, allowing it for sending '
          'starts over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('contact-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await ref.read(addressBookProvider.notifier).remove(existing.address);
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit contact' : 'Add contact'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('contact-name'),
              controller: _name,
              autofocus: !editing,
              maxLength: contactNameMaxLength,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Mom',
              ),
              validator: validateContactName,
            ),
            TextFormField(
              key: const Key('contact-address'),
              controller: _address,
              readOnly: editing,
              decoration: InputDecoration(
                labelText: 'Address',
                hintText: '0x...',
                helperText: editing
                    ? 'To change the address, add a new contact.'
                    : null,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              validator: _validateAddress,
            ),
          ],
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            key: const Key('contact-remove'),
            onPressed: _remove,
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('contact-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
