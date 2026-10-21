import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/wallet_screen.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../../../test_helpers/fakes.dart';

class _Wallet extends WalletNotifier {
  _Wallet(this.wallet);
  final WalletModel wallet;
  @override
  Future<WalletModel?> build() async => wallet;
}

class _Transactions extends TransactionsNotifier {
  @override
  Future<TransactionsState> build() async => TransactionsState.empty;
}

void main() {
  for (final amount in ['125000000', '0', null]) {
    testWidgets(
      'Earnings wires chain totals and weather paid/pending ($amount)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final wallet = WalletModel.fromJson({
          'address': 'wrf1testwallet0000000000',
          'balance': '150000000',
          'earnedBalanceTotal': '9007199254740993123456789',
          'weatherRewards': amount,
          'weatherRewardsPending': amount == null ? null : '25000000',
          'weatherRewardsUnavailable': amount == null
              ? 'This node does not report contribution rewards.'
              : 'STALE REASON MUST BE HIDDEN',
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              walletProvider.overrideWith(() => _Wallet(wallet)),
              transactionsProvider.overrideWith(_Transactions.new),
              walletSecureStorageProvider.overrideWithValue(
                FakeWalletSecureStorage(backupConfirmed: true),
              ),
            ],
            child: const MaterialApp(home: WalletScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Total earned'), findsOneWidget);
        expect(find.text('1.5 WRF'), findsOneWidget);
        expect(find.textContaining('credits'), findsNothing);
        expect(find.text('90071992547409931.23456789 WRF'), findsOneWidget);
        expect(find.text('Network Bonus'), findsNothing);
        if (amount == null) {
          expect(
            find.textContaining(
              'This node does not report contribution rewards.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Not available'), findsWidgets);
        } else {
          expect(
            find.text(amount == '0' ? '0 WRF' : '1.25 WRF'),
            findsOneWidget,
          );
          expect(find.text('0.25 WRF'), findsOneWidget);
          expect(find.textContaining('STALE REASON'), findsNothing);
          expect(find.textContaining('Not available'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
