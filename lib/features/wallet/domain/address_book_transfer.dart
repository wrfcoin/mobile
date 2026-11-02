import 'dart:convert';

import '../data/models/address_book_entry.dart';
import 'recipient_safety.dart';

/// Contacts file format. Only a name and an address per contact: no
/// allowlist state (an imported file can never skip the cooldown) and no
/// verification status (a file cannot vouch for an address).
const String addressBookFileFormat = 'wrfcoin-contacts';
const int addressBookFileVersion = 1;
const int contactNameMaxLength = 40;
const int addressBookImportMaxBytes = 256 * 1024;
const int addressBookImportMaxContacts = 1000;

/// Characters that make a name look like another one, or look different from
/// what it holds: control characters, bidi overrides and marks, zero-width and
/// invisible formatting. A "Mom" with any of these is not Mom.
final _unsafeNameCharacters = RegExp(
  '[\\u0000-\\u001F\\u007F-\\u009F\\u00AD\\u034F\\u061C\\u115F\\u1160\\u17B4\\u17B5'
  '\\u180B-\\u180F\\u200B\\u200C\\u200E\\u200F\\u2028-\\u202E\\u2060-\\u206F\\u3164'
  '\\uFE00-\\uFE0E\\uFEFF\\uFFA0\\uFFF0-\\uFFFB\\u{E0000}-\\u{E0FFF}]'
  // The two that build emoji, wherever they don't follow one.
  '|(?<![\\u{2190}-\\u{3299}\\u{1F000}-\\u{1FAFF}])\\uFE0F'
  '|(?<![\\u{2190}-\\u{3299}\\u{1F000}-\\u{1FAFF}\\uFE0F])\\u200D',
  unicode: true,
);

/// Null when [name] is a usable contact name, else the reason.
String? validateContactName(String? name) {
  final value = name?.trim() ?? '';
  if (value.isEmpty) return 'Name required';
  if (value.length > contactNameMaxLength) {
    return 'Keep the name under $contactNameMaxLength characters';
  }
  if (_unsafeNameCharacters.hasMatch(value)) {
    return 'This name has hidden characters. Type it again by hand.';
  }
  return null;
}

String exportAddressBook(List<AddressBookEntry> entries) {
  return const JsonEncoder.withIndent('  ').convert({
    'format': addressBookFileFormat,
    'version': addressBookFileVersion,
    'contacts': [
      for (final e in entries) {'name': e.label, 'address': e.address},
    ],
  });
}

/// What names are compared by: "mom", " Mom" and "MOM  " are one name.
String _nameKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class AddressBookImportResult {
  const AddressBookImportResult({
    this.added = const [],
    this.nameClashes = const [],
    this.invalid = 0,
    this.duplicates = 0,
    this.blocked = 0,
    this.error,
  });

  /// New contacts to save: unverified and not allowed.
  final List<AddressBookEntry> added;

  /// Refused: the name is already on a contact with a different address. A
  /// contact's address never changes, and two Moms are how a file spoofs one.
  final List<AddressBookEntry> nameClashes;

  /// Rows with a bad name or an address Send would not accept.
  final int invalid;

  /// Addresses already saved (the saved contact is kept as is).
  final int duplicates;

  /// Addresses this device knows are legacy receive-only.
  final int blocked;

  /// The file could not be read as a contacts file at all.
  final String? error;

  String get summary {
    if (error != null) return error!;
    final parts = <String>[
      'Added ${added.length} contact${added.length == 1 ? '' : 's'}',
      if (duplicates > 0) '$duplicates already saved',
      if (nameClashes.isNotEmpty)
        '${nameClashes.length} skipped (name already used)',
      if (invalid > 0) '$invalid skipped (bad name or address)',
      if (blocked > 0) '$blocked skipped (receive-only address)',
    ];
    return parts.join(', ');
  }
}

/// Reads a contacts file. Every address passes the same checks Send uses:
/// [isSendableAddress] and [assessRecipient] (known legacy addresses are
/// skipped). Only a name and an address are ever taken from a row, so a file
/// can't allow a contact, and nothing here changes a saved contact.
AddressBookImportResult importAddressBook(
  String raw, {
  required List<AddressBookEntry> existing,
  String? ownLegacyAlias,
}) {
  const notAFile = AddressBookImportResult(
    error: 'This is not a WRFCoin contacts file.',
  );
  if (utf8.encode(raw).length > addressBookImportMaxBytes) {
    return const AddressBookImportResult(error: 'This file is too large.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return notAFile;
  }
  if (decoded is! Map ||
      decoded['format'] != addressBookFileFormat ||
      decoded['contacts'] is! List) {
    return notAFile;
  }
  if (decoded['version'] != addressBookFileVersion) {
    return const AddressBookImportResult(
      error: 'This contacts file is from a newer app version.',
    );
  }
  final rows = decoded['contacts'] as List;
  if (rows.length > addressBookImportMaxContacts) {
    return const AddressBookImportResult(
      error: 'This file has too many contacts.',
    );
  }

  final seen = {for (final e in existing) e.address.trim().toLowerCase()};
  final names = {for (final e in existing) _nameKey(e.label)};
  final added = <AddressBookEntry>[];
  final nameClashes = <AddressBookEntry>[];
  var invalid = 0, duplicates = 0, blocked = 0;
  for (final row in rows) {
    if (row is! Map) {
      invalid++;
      continue;
    }
    final name = row['name'];
    final address = row['address'];
    if (name is! String ||
        address is! String ||
        validateContactName(name) != null ||
        address != address.trim() ||
        !isSendableAddress(address) ||
        BigInt.tryParse(address) == BigInt.zero) {
      invalid++;
      continue;
    }
    final key = address.trim().toLowerCase();
    if (seen.contains(key)) {
      duplicates++;
      continue;
    }
    if (assessRecipient(
      to: address,
      addressBook: existing,
      ownLegacyAlias: ownLegacyAlias,
    ).blocksSend) {
      blocked++;
      continue;
    }
    final entry = AddressBookEntry(label: name.trim(), address: address);
    if (!names.add(_nameKey(name))) {
      nameClashes.add(entry);
      continue;
    }
    seen.add(key);
    added.add(entry);
  }
  return AddressBookImportResult(
    added: added,
    nameClashes: nameClashes,
    invalid: invalid,
    duplicates: duplicates,
    blocked: blocked,
  );
}
