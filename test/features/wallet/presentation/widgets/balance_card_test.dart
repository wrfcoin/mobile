import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/balance_card.dart';

void main() {
  for (final entry in {
    '150000000': '1.5',
    '9007199254740993123456789': '90071992547409931.23456789',
  }.entries) {
    testWidgets('balance and earned total share WRF units (${entry.key})', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BalanceCard(
              address: 'wrf1234567890abcdef',
              balance: entry.key,
              earnedBalanceTotal: '250000000',
            ),
          ),
        ),
      );
      expect(find.text('${entry.value} WRF'), findsOneWidget);
      expect(find.text('2.5 WRF'), findsOneWidget);
      expect(find.textContaining('credits'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'missing reward totals show Not available and keep zero balance',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BalanceCard(address: 'wrf1234567890abcdef', balance: '0'),
          ),
        ),
      );
      expect(find.text('Not available'), findsNWidgets(3));
      expect(
        find.text('0 WRF'),
        findsOneWidget,
        reason: 'only the real balance',
      );
    },
  );

  testWidgets('reported zero rewards are displayed as zero', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BalanceCard(
            address: 'wrf1234567890abcdef',
            balance: '0',
            weatherRewards: '0',
            earnedBalanceTotal: '0',
            weatherRewardsPending: '0',
          ),
        ),
      ),
    );
    expect(find.textContaining('credits'), findsNothing);
    expect(find.text('0 WRF'), findsNWidgets(4));
    expect(find.text('Not available'), findsNothing);
  });

  Widget buildSubject() {
    return const MaterialApp(
      home: Scaffold(
        body: BalanceCard(
          address: 'wrf1234567890abcdef',
          balance: '123.45',
          weatherRewards: '892000000',
          earnedBalanceTotal: '1245000000',
          weatherRewardsPending: '25000000',
          pendingTransactions: 2,
        ),
      ),
    );
  }

  testWidgets('renders masked address and balance', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('wrf123...cdef'), findsOneWidget);
    expect(find.text('123.45 WRF'), findsOneWidget);
  });

  testWidgets('shows pending transaction count', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('2 processing'), findsOneWidget);
    expect(find.byTooltip('Copy wallet address'), findsOneWidget);
    expect(find.text('8.92 WRF'), findsOneWidget);
    expect(find.text('12.45 WRF'), findsOneWidget);
  });
}
