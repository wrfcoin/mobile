import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/address_book_transfer.dart';

const _mom = '0x1111111111111111111111111111111111111111';
const _dad = '0x2222222222222222222222222222222222222222';
const _legacy = '0x3333333333333333333333333333333333333333';

String _file(List<Object?> contacts, {int version = 1}) => jsonEncode({
  'format': addressBookFileFormat,
  'version': version,
  'contacts': contacts,
});

void main() {
  test('export holds only names and addresses', () {
    final json = exportAddressBook([
      AddressBookEntry(
        label: 'Mom',
        address: _mom,
        status: AddressStatus.verifiedCurrent,
        allowedFrom: DateTime.utc(2026),
      ),
    ]);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['format'], addressBookFileFormat);
    expect(decoded['contacts'], [
      {'name': 'Mom', 'address': _mom},
    ]);
  });

  test('export then import restores the contacts, never allowed', () {
    final exported = exportAddressBook([
      AddressBookEntry(
        label: 'Mom',
        address: _mom,
        allowedFrom: DateTime(2026),
      ),
      const AddressBookEntry(label: 'Dad', address: _dad),
    ]);
    final result = importAddressBook(exported, existing: const []);
    expect(result.error, isNull);
    expect(result.added.map((e) => e.label), ['Mom', 'Dad']);
    expect(result.added.every((e) => e.allowedFrom == null), isTrue);
    expect(
      result.added.every((e) => e.status == AddressStatus.unverified),
      isTrue,
    );
    expect(result.summary, 'Added 2 contacts');
  });

  test('a file cannot smuggle in allowlist or verified status', () {
    final result = importAddressBook(
      _file([
        {
          'name': 'Mom',
          'address': _mom,
          'allowed_from': 0,
          'status': 'verifiedCurrent',
        },
      ]),
      existing: const [],
    );
    expect(result.added.single.allowedFrom, isNull);
    expect(result.added.single.status, AddressStatus.unverified);
  });

  test('bad rows, duplicates and legacy addresses are skipped', () {
    final result = importAddressBook(
      _file([
        {
          'name': 'Mom again',
          'address': _mom.toUpperCase().replaceAll('0X', '0x'),
        },
        {'name': '', 'address': _dad},
        {'name': 'x' * 41, 'address': _dad},
        {'name': 'Bad', 'address': 'wrf1notanaddress'},
        {'name': 'Short', 'address': '0x1234'},
        'not a row',
        {'name': 'Old', 'address': _legacy},
        {'name': 'Dad', 'address': _dad},
        {'name': 'Dad twice', 'address': _dad},
      ]),
      existing: const [AddressBookEntry(label: 'Mom', address: _mom)],
      ownLegacyAlias: _legacy,
    );
    expect(result.added.map((e) => e.label), ['Dad']);
    expect(result.duplicates, 2);
    expect(result.invalid, 5);
    expect(result.blocked, 1);
    expect(
      result.summary,
      'Added 1 contact, 2 already saved, 5 skipped (bad name or address), '
      '1 skipped (receive-only address)',
    );
  });

  test('files that are not contacts files are refused', () {
    for (final raw in [
      'not json',
      '[]',
      jsonEncode({'format': 'other', 'contacts': []}),
      jsonEncode({'format': addressBookFileFormat}),
    ]) {
      final r = importAddressBook(raw, existing: const []);
      expect(r.error, 'This is not a WRFCoin contacts file.', reason: raw);
      expect(r.added, isEmpty);
    }
    expect(
      importAddressBook(_file([], version: 2), existing: const []).error,
      'This contacts file is from a newer app version.',
    );
    expect(
      importAddressBook(
        'x' * (addressBookImportMaxBytes + 1),
        existing: const [],
      ).error,
      'This file is too large.',
    );
  });

  test('contact names are short and required', () {
    expect(validateContactName('Mom'), isNull);
    expect(validateContactName('  '), 'Name required');
    expect(validateContactName('x' * 41), isNotNull);
  });
}
