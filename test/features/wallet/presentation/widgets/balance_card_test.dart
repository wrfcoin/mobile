import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/balance_card.dart';

Widget _card({
  String? balance,
  String? earned,
  BalanceAvailability availability = BalanceAvailability.reported,
  int pending = 0,
}) => MaterialApp(
  home: Scaffold(
    body: BalanceCard(
      address: 'wrf1234567890abcdef',
      balance: balance,
      balanceAvailability: availability,
      earnedBalanceTotal: earned,
      pendingTransactions: pending,
    ),
  ),
);

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  for (final entry in {
    '150000000': '1.5',
    '9007199254740993123456789': '90071992547409931.23456789',
  }.entries) {
    testWidgets('balance and earned in total share WRF units (${entry.key})', (
      tester,
    ) async {
      await tester.pumpWidget(_card(balance: entry.key, earned: '250000000'));
      expect(_text(tester, 'balance-card-balance'), '${entry.value} WRF');
      expect(find.text('Earned in total'), findsOneWidget);
      expect(_text(tester, 'balance-card-earned'), '2.5 WRF');
      expect(find.text('Test coins have no value.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reported zeros are shown as zero', (tester) async {
    await tester.pumpWidget(_card(balance: '0', earned: '0'));
    expect(_text(tester, 'balance-card-balance'), '0 WRF');
    expect(_text(tester, 'balance-card-earned'), '0 WRF');
  });

  testWidgets('a missing earned total is Unavailable, never zero', (
    tester,
  ) async {
    await tester.pumpWidget(_card(balance: '0'));
    expect(_text(tester, 'balance-card-balance'), '0 WRF');
    expect(_text(tester, 'balance-card-earned'), 'Unavailable');
    expect(find.text('0 WRF'), findsOneWidget, reason: 'only the balance');
  });

  testWidgets('public reads switched off show Unavailable', (tester) async {
    await tester.pumpWidget(
      _card(availability: BalanceAvailability.unavailable),
    );
    expect(_text(tester, 'balance-card-balance'), 'Unavailable');
    expect(_text(tester, 'balance-card-earned'), 'Unavailable');
    expect(find.textContaining('WRF'), findsNothing);
  });

  testWidgets('a rate-limited read shows Busy', (tester) async {
    await tester.pumpWidget(_card(availability: BalanceAvailability.busy));
    expect(_text(tester, 'balance-card-balance'), 'Busy');
    expect(_text(tester, 'balance-card-earned'), 'Busy');
  });

  testWidgets('no income claims on the card', (tester) async {
    await tester.pumpWidget(_card(balance: '100', earned: '100'));
    for (final claim in ['income', 'profit', 'yield', 'APY', 'per day']) {
      expect(find.textContaining(claim), findsNothing);
    }
  });

  testWidgets('renders masked address and pending count', (tester) async {
    await tester.pumpWidget(_card(balance: '12345000000', pending: 2));
    expect(find.text('wrf123...cdef'), findsOneWidget);
    expect(_text(tester, 'balance-card-balance'), '123.45 WRF');
    expect(find.text('2 processing'), findsOneWidget);
    expect(find.byTooltip('Copy wallet address'), findsOneWidget);
  });

  testWidgets('fits a 320 px phone with a long balance', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _card(balance: '9007199254740993123456789', earned: '9007199254740993'),
    );
    expect(tester.takeException(), isNull);
  });
}
