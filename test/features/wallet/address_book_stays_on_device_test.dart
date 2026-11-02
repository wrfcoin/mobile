import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The address book and the send allowlist are device-only. This guards the
/// wiring: no network code reads them. (A source scan, not proof; the PR
/// that added it lists every reader.)
void main() {
  test('no network-layer file touches the address book or allowlist', () {
    final readers = <String>[];
    final pattern = RegExp(
      r'addressBookProvider|getAddressBook|AddressBookEntry|'
      r'sendAllowlistProvider|getSendAllowlist',
    );
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (pattern.hasMatch(file.readAsStringSync())) {
        readers.add(file.path.replaceAll(r'\', '/'));
      }
    }
    expect(readers, isNotEmpty);
    final network = readers.where(
      (p) =>
          p.contains('/services/api/') ||
          p.contains('/datasources/') ||
          p.contains('/repositories/') ||
          p.contains('/background/') ||
          p.contains('/observability/'),
    );
    expect(network, isEmpty, reason: 'device-only data reached: $network');
  });
}
