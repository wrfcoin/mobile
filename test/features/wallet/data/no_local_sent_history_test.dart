import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wallet history has no device-local sent-transfer ledger or insert', () {
    final sources = [
      File('lib/features/wallet/data/datasources/wallet_remote_datasource.dart')
          .readAsStringSync(),
      File('lib/features/wallet/data/repositories/wallet_repository_impl.dart')
          .readAsStringSync(),
      File('lib/features/wallet/presentation/screens/send_screen.dart')
          .readAsStringSync(),
    ].join('\n').toLowerCase();

    expect(sources, isNot(contains('localsenttransfer')));
    expect(
      sources,
      isNot(matches(RegExp(r'insert.{0,40}sent.{0,20}transaction'))),
    );
  });
}
