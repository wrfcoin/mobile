import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/testnet_notice.dart';

void main() {
  testWidgets('testnet expectations and canonical URL are visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TestnetNotice())),
    );
    expect(
      find.text(
        'This is a test network. It may be reset without notice. Balances and tokens have no monetary value. No migration to mainnet is promised or implied. Please attach no production bridges, exchange listings or irreplaceable assets.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'https://wrfcoin.com/testnet-disclaimer.html',
      ),
      findsOneWidget,
    );
  });

  test('wallet mounts the notice outside asynchronous wallet states', () {
    final source = File(
      'lib/features/wallet/presentation/screens/wallet_screen.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('bottomNavigationBar: const SafeArea(child: TestnetNotice()),'),
    );
  });
}
