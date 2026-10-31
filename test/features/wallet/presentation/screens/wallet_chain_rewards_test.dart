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
  final cases = <String, (WalletModel, String, String)>{
    'reported': (
      const WalletModel(
        address: 'wrf1testwallet0000000000',
        balance: '150000000',
        earnedBalanceTotal: '9007199254740993123456789',
      ),
      '1.5 WRF',
      '90071992547409931.23456789 WRF',
    ),
    'earned not reported': (
      const WalletModel(address: 'wrf1testwallet0000000000', balance: '0'),
      '0 WRF',
      'Unavailable',
    ),
    'public reads off (404)': (
      const WalletModel(
        address: 'wrf1testwallet0000000000',
        balance: null,
        balanceAvailability: BalanceAvailability.unavailable,
      ),
      'Unavailable',
      'Unavailable',
    ),
    'rate limited (429)': (
      const WalletModel(
        address: 'wrf1testwallet0000000000',
        balance: null,
        balanceAvailability: BalanceAvailability.busy,
      ),
      'Busy',
      'Busy',
    ),
  };
  for (final entry in cases.entries) {
    testWidgets(
      'wallet screen wires balance and earned in total (${entry.key})',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final (wallet, balance, earned) = entry.value;
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
        Text text(String key) => tester.widget<Text>(find.byKey(Key(key)));
        expect(text('balance-card-balance').data, balance);
        expect(find.text('Earned in total'), findsOneWidget);
        expect(text('balance-card-earned').data, earned);
        expect(find.textContaining('credits'), findsNothing);
        expect(find.text('Network Bonus'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
