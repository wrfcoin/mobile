import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_earned_provider.dart';

void main() {
  WalletModel wallet(String? earned) => WalletModel(
    address: 'wrf1wallet',
    balance: '0',
    earnedBalanceTotal: earned,
  );

  test('earned base units become WRF (1 WRF = 10^8 base units)', () {
    expect(walletEarnedWrfDisplay(wallet('100000000')), '1');
    expect(walletEarnedWrfDisplay(wallet('150000000')), '1.5');
    expect(walletEarnedWrfDisplay(wallet('1')), '0.00000001');
    expect(walletEarnedWrfDisplay(wallet('0')), '0');
  });

  test('no wallet, an unreported or a malformed earned shows nothing', () {
    expect(walletEarnedWrfDisplay(null), isNull);
    expect(walletEarnedWrfDisplay(wallet(null)), isNull);
    expect(walletEarnedWrfDisplay(wallet('1.25')), isNull);
  });
}
