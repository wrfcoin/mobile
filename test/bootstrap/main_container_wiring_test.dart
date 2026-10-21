import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main uses the tested app container factory exclusively', () {
    // The runtime app-shell test exercises createAppContainer. This source
    // gate separately ties the shipped entrypoint to that tested bootstrap.
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('await createAppContainer()'));
    expect(source, isNot(contains('buildAppOverrides(')));
    expect(source, isNot(contains('ProviderContainer(')));
  });
}
