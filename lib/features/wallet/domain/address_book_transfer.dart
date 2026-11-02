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

/// Null when [name] is a usable contact name, else the reason.
String? validateContactName(String? name) {
  final value = name?.trim() ?? '';
  if (value.isEmpty) return 'Name required';
  if (value.length > contactNameMaxLength) {
    return 'Keep the name under $contactNameMaxLength characters';
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

class AddressBookImportResult {
  const AddressBookImportResult({
    this.added = const [],
    this.invalid = 0,
    this.duplicates = 0,
    this.blocked = 0,
    this.error,
  });

  /// New contacts to save: unverified and not allowed.
  final List<AddressBookEntry> added;

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
      if (invalid > 0) '$invalid skipped (bad name or address)',
      if (blocked > 0) '$blocked skipped (receive-only address)',
    ];
    return parts.join(', ');
  }
}

/// Reads a contacts file. Every address passes the same checks Send uses:
/// [isSendableAddress] and [assessRecipient] (known legacy addresses are
/// skipped).
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
  } on FormatException {
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
  final added = <AddressBookEntry>[];
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
        !isSendableAddress(address)) {
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
    seen.add(key);
    added.add(AddressBookEntry(label: name.trim(), address: address.trim()));
  }
  return AddressBookImportResult(
    added: added,
    invalid: invalid,
    duplicates: duplicates,
    blocked: blocked,
  );
}
