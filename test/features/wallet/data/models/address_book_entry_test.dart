import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';

void main() {
  group('AddressBookEntry', () {
    test('fromJson tolerates missing fields', () {
      final empty = AddressBookEntry.fromJson(const <String, dynamic>{});
      expect(empty.label, '');
      expect(empty.address, '');

      final partial = AddressBookEntry.fromJson(const <String, dynamic>{
        'label': 'Alice',
      });
      expect(partial.label, 'Alice');
      expect(partial.address, '');
    });

    test('fromJson/toJson roundtrip preserves data', () {
      const original = AddressBookEntry(
        label: '  Bob  ',
        address: ' wrf1abc123 ',
      );
      final json = original.toJson();
      final restored = AddressBookEntry.fromJson(json);

      // fromJson trims whitespace
      expect(restored.label, 'Bob');
      expect(restored.address, 'wrf1abc123');

      // Second roundtrip is stable
      final json2 = restored.toJson();
      final restored2 = AddressBookEntry.fromJson(json2);
      expect(restored2.label, restored.label);
      expect(restored2.address, restored.address);
    });
  });
}
