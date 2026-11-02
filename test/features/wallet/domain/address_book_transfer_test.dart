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

  group('safety rules', () {
    const mom = AddressBookEntry(label: 'Mom', address: _mom);

    test('every address is checked strictly', () {
      for (final bad in [
        '0x123',
        '${_dad}0',
        _dad.substring(2),
        '0X${_dad.substring(2)}',
        ' $_dad',
        '$_dad\n',
        '0x${'g' * 40}',
        '0x${'0' * 40}',
        '\u202E$_dad',
      ]) {
        final r = importAddressBook(
          _file([
            {'name': 'Bad', 'address': bad},
          ]),
          existing: const [],
        );
        expect(r.added, isEmpty, reason: bad);
        expect(r.invalid, 1, reason: bad);
      }
    });

    test('too many contacts refuses the whole file', () {
      final at = [
        for (var i = 0; i < addressBookImportMaxContacts; i++)
          {
            'name': 'C$i',
            'address': '0x${(i + 1).toRadixString(16).padLeft(40, '0')}',
          },
      ];
      expect(
        importAddressBook(_file(at), existing: const []).added,
        hasLength(addressBookImportMaxContacts),
      );
      expect(
        importAddressBook(
          _file([
            ...at,
            {'name': 'One more', 'address': _dad},
          ]),
          existing: const [],
        ).error,
        'This file has too many contacts.',
      );
    });

    for (final name in [
      'x' * (contactNameMaxLength + 1),
      'M\u0000om',
      'Mom\nDad',
      'M\u007Fom',
      'M\u0085om',
      '\u202EmoM',
      'M\u202Dom',
      'Mo\u2066m',
      'M\u200Fom',
      'M\u061Com',
      'M\u200Bom',
      'M\u200Dom',
      'M\u00ADom',
      'Mo\u{E0041}m',
      'M\uFEFFom',
      'M\u200Com',
      'Mom\uFE0F',
      'M\u2028om',
    ]) {
      test('the name ${jsonEncode(name)} is refused', () {
        expect(validateContactName(name), isNotNull);
        final r = importAddressBook(
          _file([
            {'name': name, 'address': _dad},
          ]),
          existing: const [],
        );
        expect(r.added, isEmpty);
        expect(r.invalid, 1);
      });
    }

    test('ordinary names from any language are fine', () {
      for (final name in [
        'Mom',
        'María',
        'ماما',
        '妈妈',
        'Mom 🌦',
        "O'Brien",
        'Mom ❤\uFE0F',
        '👨\u200D👩\u200D👧',
        '❤\uFE0F\u200D🔥',
      ]) {
        expect(validateContactName(name), isNull, reason: name);
      }
    });

    test('a same-name different-address row is flagged, never merged', () {
      for (final same in ['Mom', 'mom', ' MOM ']) {
        final r = importAddressBook(
          _file([
            {'name': same, 'address': _dad},
          ]),
          existing: const [mom],
        );
        expect(r.added, isEmpty, reason: same);
        expect(r.nameClashes.single.address, _dad);
      }
    });

    test('two rows in one file cannot share a name', () {
      final r = importAddressBook(
        _file([
          {'name': 'Pat', 'address': _dad},
          {'name': 'pat', 'address': _legacy},
        ]),
        existing: const [],
      );
      expect(r.added.single.address, _dad);
      expect(r.nameClashes.single.address, _legacy);
    });

    test('a known address under a new name changes nothing', () {
      final r = importAddressBook(
        _file([
          {'name': 'Not Mom', 'address': _mom},
        ]),
        existing: const [mom],
      );
      expect(r.added, isEmpty);
      expect(r.nameClashes, isEmpty);
      expect(r.duplicates, 1);
    });

    test('nothing but a name and an address is taken from a row', () {
      final r = importAddressBook(
        _file([
          {
            'name': 'Dad',
            'address': _dad,
            'allowed_from': 0,
            'allowedFrom': 0,
            'status': 'verifiedCurrent',
            'replacement': _mom,
          },
        ]),
        existing: const [],
      );
      final entry = r.added.single;
      expect(entry.allowedFrom, isNull);
      expect(entry.status, AddressStatus.unverified);
      expect(entry.replacementAddress, isNull);
    });
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
