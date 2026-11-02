import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/address_book_transfer.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/address_book_screen.dart';

/// Like the Android plugin's file: its name comes from its path, and it says
/// how long it is without being read.
class _File extends XFile {
  _File(this.fileName, this.bytes, {int? reportedLength})
    : reported = reportedLength ?? bytes.length,
      super.fromData(bytes, path: '/cache/$fileName');

  final String fileName;
  final Uint8List bytes;
  final int reported;
  int reads = 0;

  @override
  Future<int> length() async => reported;

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return bytes;
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      throw StateError('never: on Android this ignores the encoding');
}

_File _utf8(String name, String text) =>
    _File(name, Uint8List.fromList(utf8.encode(text)));

Matcher _rejected(String message) => throwsA(
  isA<ContactsFileRejected>().having((e) => e.message, 'message', message),
);

void main() {
  test('a .json file reads as text, in any case of extension', () async {
    expect(await readContactsFile(_utf8('a.json', '{}')), '{}');
    expect(await readContactsFile(_utf8('A.JSON', '{}')), '{}');
  });

  test('non-English names survive, which readAsString on Android broke', () {
    expect(
      readContactsFile(_utf8('a.json', 'María 妈妈')),
      completion('María 妈妈'),
    );
  });

  test('a byte order mark from a text editor is not a failure', () {
    expect(readContactsFile(_utf8('a.json', '﻿{}')), completion('{}'));
  });

  for (final name in [
    'a.pdf',
    'a.docx',
    'a.json.pdf',
    'a.jsonx',
    'json',
    'a',
  ]) {
    test('$name is refused without being read', () async {
      final file = _utf8(name, '{}');
      await expectLater(
        readContactsFile(file),
        _rejected('Choose a WRFCoin contacts file. Its name ends in .json.'),
      );
      expect(file.reads, 0);
    });
  }

  test('a file over the cap is refused without being read', () async {
    final file = _File(
      'a.json',
      Uint8List(0),
      reportedLength: addressBookImportMaxBytes + 1,
    );
    await expectLater(
      readContactsFile(file),
      _rejected('This file is too large.'),
    );
    expect(file.reads, 0);
  });

  test('a file exactly at the cap is read', () async {
    final file = _File('a.json', Uint8List(addressBookImportMaxBytes));
    await readContactsFile(file);
    expect(file.reads, 1);
  });

  test('a file that said it was small but is not is still refused', () {
    final file = _File(
      'a.json',
      Uint8List(addressBookImportMaxBytes + 1),
      reportedLength: 10,
    );
    expect(readContactsFile(file), _rejected('This file is too large.'));
  });

  test('bytes that are not UTF-8 get the plain message', () {
    final file = _File('a.json', Uint8List.fromList([0x7B, 0xFF, 0xFE, 0x7D]));
    expect(
      readContactsFile(file),
      _rejected('This is not a WRFCoin contacts file.'),
    );
  });

  test('a real file on disk reads through the same path', () async {
    final dir = await Directory.systemTemp.createTemp('contacts');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/wrfcoin-contacts.json';
    await File(path).writeAsString('{"a":"María"}');
    expect(await readContactsFile(XFile(path)), '{"a":"María"}');
  });
}
