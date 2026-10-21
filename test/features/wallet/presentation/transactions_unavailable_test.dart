import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/transaction_history_unavailable_card.dart';

void main() {
  testWidgets('501 history state is calm, explicit, and has no retry or rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TransactionHistoryUnavailableCard()),
      ),
    );

    expect(
      find.text('Transaction history is not available on the testnet yet'),
      findsOneWidget,
    );
    expect(find.textContaining('Retry'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });
}
