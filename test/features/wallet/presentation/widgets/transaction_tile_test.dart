import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/transaction_tile.dart';

void main() {
  Future<void> pumpTile(WidgetTester tester, TransactionModel transaction) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransactionTile(transaction: transaction)),
      ),
    );
  }

  for (final entry in {
    'ContributionCommit': 'Weather data commit',
    'ContributionReveal': 'Weather data reveal',
    'StationRegistration': 'Station registration',
    'FutureOperation': 'Network operation',
    'Stake': 'Stake operation',
    'ConfidentialTransfer': 'Private transfer',
  }.entries) {
    testWidgets('${entry.key} has an operation label without monetary claims', (
      tester,
    ) async {
      await pumpTile(
        tester,
        TransactionModel(
          hash: 'operation',
          from: 'network',
          type: entry.key,
          direction: 'outgoing',
          value: '25000000000',
          settlement: 'included',
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Included on chain'), findsOneWidget);
      expect(find.text('Direction not reported'), findsNothing);
      expect(find.textContaining('WRF'), findsNothing);
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
      expect(find.byIcon(Icons.swap_vert), findsNothing);
    });
  }
  testWidgets('self transfer has unsigned amount', (tester) async {
    await pumpTile(
      tester,
      const TransactionModel(
        hash: 'self',
        from: 'own',
        type: 'Transfer',
        direction: 'self',
        value: '100000000',
        settlement: 'included',
      ),
    );
    expect(find.text('Self transfer'), findsOneWidget);
    expect(find.text('1 WRF'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
    expect(find.textContaining('-'), findsNothing);
  });
  testWidgets('paid weather reward remains received', (tester) async {
    await pumpTile(
      tester,
      const TransactionModel(
        hash: '',
        eventId: 'contribution:paid',
        from: '',
        type: 'weather_reward',
        direction: 'incoming',
        value: '150000000',
        settlement: 'paid',
      ),
    );
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Weather reward'), findsOneWidget);
    expect(find.text('+1.5 WRF'), findsOneWidget);
  });

  testWidgets('renders incoming transaction details', (tester) async {
    await pumpTile(
      tester,
      const TransactionModel(
        hash: '0x1',
        timestamp: '2026-03-10T00:00:00Z',
        from: 'wrf1234567890abcdef',
        to: 'wrf0987654321fedcba',
        value: '1000000000',
        direction: 'incoming',
        status: 'confirmed',
      ),
    );

    expect(find.text('Received'), findsOneWidget);
    expect(find.text('+10 WRF'), findsOneWidget);
    expect(find.textContaining('From:'), findsOneWidget);
  });

  testWidgets('renders outgoing transaction details', (tester) async {
    await pumpTile(
      tester,
      const TransactionModel(
        hash: '0x2',
        timestamp: '2026-03-10T00:00:00Z',
        from: 'wrf1234567890abcdef',
        to: 'wrf0987654321fedcba',
        value: '700000000',
        direction: 'outgoing',
        status: 'pending',
      ),
    );

    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('-7 WRF'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('generic failed reward does not claim received payment', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const TransactionModel(
        hash: '0x3',
        timestamp: '2026-03-10T00:00:00Z',
        from: 'network',
        to: 'wrf0987654321fedcba',
        value: '300000000',
        direction: 'incoming',
        type: 'reward',
        status: 'failed',
      ),
    );

    expect(find.text('Reward operation'), findsOneWidget);
    expect(find.text('Direction not reported'), findsNothing);
    expect(find.text('3 WRF'), findsNothing);
    expect(find.text('+3 WRF'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('unknown direction and missing amount are shown as such', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const TransactionModel(hash: '0x4', from: '', blockNumber: 88),
    );

    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('Direction not reported'), findsOneWidget);
    expect(find.text('Amount not reported'), findsOneWidget);
    expect(find.textContaining('credits'), findsNothing);
    expect(find.text('Block 88'), findsOneWidget);
    expect(find.text('Sent'), findsNothing);
    expect(find.text('Received'), findsNothing);
  });

  testWidgets('received with an unreported amount carries no sign', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const TransactionModel(
        hash: '0x5',
        from: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        direction: 'incoming',
      ),
    );

    expect(find.text('Received'), findsOneWidget);
    expect(find.textContaining('From:'), findsOneWidget);
    expect(find.text('Amount not reported'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
  });
  testWidgets('u128 received amount fits a phone-sized row', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTile(
      tester,
      const TransactionModel(
        hash: '',
        from: '',
        type: 'forecast_reward',
        direction: 'incoming',
        settlement: 'paid',
        value: '340282366920938463463374607431768211455',
      ),
    );
    expect(
      find.text('+3402823669209384634633746074317.68211455 WRF'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
