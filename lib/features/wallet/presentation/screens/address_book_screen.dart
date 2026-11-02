import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// A picked file that can't be a contacts file; [message] is for the user.
class ContactsFileRejected implements Exception {
  const ContactsFileRejected(this.message);

  final String message;

  static const notContacts = ContactsFileRejected(
    'This is not a WRFCoin contacts file.',
  );
}

/// Checks a picked file before its contents are decoded: the name, then the
/// size, then strict UTF-8. Reads bytes, not [XFile.readAsString], which on
/// Android treats each byte as a character.
Future<String> readContactsFile(XFile file) async {
  if (!file.name.toLowerCase().endsWith('.json')) {
    throw const ContactsFileRejected(
      'Choose a WRFCoin contacts file. Its name ends in .json.',
    );
  }
  if (await file.length() > addressBookImportMaxBytes) {
    throw const ContactsFileRejected('This file is too large.');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > addressBookImportMaxBytes) {
    throw const ContactsFileRejected('This file is too large.');
  }
  try {
    final text = utf8.decode(bytes);
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  } on FormatException {
    throw ContactsFileRejected.notContacts;
  }
}

/// Opens and shares contacts files. Overridden in tests.
class ContactsFileGateway {
  const ContactsFileGateway();

  /// The text of a file the user picks, or null if they cancel. Throws
  /// [ContactsFileRejected] for a file that fails [readContactsFile].
  ///
  /// The type group only asks the system picker to filter. Android leaves that
  /// to the picker and whichever file app it opens, so nothing here relies on it.
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
    return file == null ? null : readContactsFile(file);
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
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    try {
      final raw = await ref.read(contactsFileGatewayProvider).pickFile();
      if (raw == null) return;
      final result = importAddressBook(
        raw,
        existing: await ref.read(addressBookProvider.future),
        ownLegacyAlias: await ref.read(keyManagerProvider).getOwnLegacyAlias(),
      );
      if (result.error != null) return say(result.error!);
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ImportPreview(result: result),
      );
      if (confirmed != true) return;
      await ref.read(addressBookProvider.notifier).addAll(result.added);
      say(
        '${result.summary}. Imported contacts are not allowed for sending '
        'until you allow them.',
      );
    } on ContactsFileRejected catch (e) {
      say(e.message);
    } catch (_) {
      say('That file could not be opened.');
    }
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

/// What an import would do, before anything is saved.
class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.result});

  final AddressBookImportResult result;

  @override
  Widget build(BuildContext context) {
    final added = result.added;
    final skipped = <String>[
      if (result.duplicates > 0) '${result.duplicates} already saved',
      if (result.invalid > 0) '${result.invalid} with a bad name or address',
      if (result.blocked > 0) '${result.blocked} receive-only',
    ];
    return AlertDialog(
      key: const Key('contacts-import-preview'),
      title: Text(
        added.isEmpty
            ? 'Nothing to add'
            : 'Add ${added.length} contact${added.length == 1 ? '' : 's'}?',
      ),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (added.isNotEmpty) ...[
              const Text(
                'Check each address. They are not allowed for sending until '
                'you allow them.',
              ),
              const SizedBox(height: 8),
              for (final entry in added) _PreviewRow(entry: entry),
            ],
            if (result.nameClashes.isNotEmpty) ...[
              const SizedBox(height: 12),
              SafetyNotice(
                key: const Key('contacts-import-name-clashes'),
                tone: SafetyTone.caution,
                title: 'Not added: name already used',
                body:
                    'You already have a contact with each of these names and '
                    'a different address. Saved contacts never change.',
                children: [
                  for (final entry in result.nameClashes)
                    _PreviewRow(entry: entry),
                ],
              ),
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Also skipped: ${skipped.join(', ')}.'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(added.isEmpty ? 'Close' : 'Cancel'),
        ),
        if (added.isNotEmpty)
          FilledButton(
            key: const Key('contacts-import-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Add ${added.length}'),
          ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.entry});

  final AddressBookEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        SelectableText(
          entry.address,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    ),
  );
}

/// `0x1747…a275`, the short form used for addresses elsewhere in the app.
String shortContactAddress(String address) => address.length > 14
    ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
    : address;

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
        // One short line, like addresses elsewhere. Tapping the contact shows
        // the whole address and a copy button.
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shortContactAddress(entry.address),
              key: Key('contact-short-${entry.address}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            if (chip != null) ...[const SizedBox(height: 4), chip],
          ],
        ),
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
  bool _copied = false;

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
              // A saved address is shown whole: the list only has the short form.
              maxLines: editing ? null : 1,
              decoration: InputDecoration(
                labelText: 'Address',
                hintText: '0x...',
                helperText: !editing
                    ? null
                    : _copied
                    ? 'Address copied.'
                    : 'To change the address, add a new contact.',
                suffixIcon: editing
                    ? IconButton(
                        key: const Key('contact-copy-address'),
                        tooltip: 'Copy address',
                        icon: Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 18,
                        ),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: widget.existing!.address),
                          );
                          if (mounted) setState(() => _copied = true);
                        },
                      )
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
