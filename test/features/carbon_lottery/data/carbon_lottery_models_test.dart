import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/data/models/carbon_lottery_models.dart';

void main() {
  test('parses carbon lottery dashboard payload variants', () {
    final snapshot = CarbonLotterySnapshot.fromJson({
      'data': {
        'dashboard': {
          'currentEpoch': '7',
          'endsAt': '2026-06-01T12:00:00Z',
          'jackpot': '1,250.50 credits',
          'projectedYield': 88.25,
          'tvl': '91000',
          'principal': '120',
          'principalSafe': true,
          'recentWinners': [
            {
              'id': 'winner-1',
              'epochNumber': 6,
              'title': 'Winner payout',
              'amount': '77.5',
              'winner': 'wrf123',
              'createdAt': '2026-05-30T00:00:00Z',
            },
          ],
        },
      },
    });

    expect(snapshot.epoch, 7);
    expect(snapshot.jackpotCredits, '1250.50');
    expect(snapshot.projectedYieldCredits, '88.25');
    expect(snapshot.totalDepositedCredits, '91000');
    expect(snapshot.userDepositCredits, '120');
    expect(snapshot.principalProtected, isTrue);
    expect(snapshot.history.single.label, 'Winner payout');
    expect(snapshot.history.single.amountCredits, '77.5');
  });

  test('parses signed transaction request response', () {
    final request = CarbonLotteryActionRequest.fromJson(
      {
        'data': {
          'transaction': {
            'requestId': 'req-1',
            'status': 'submitted',
            'amount': '25 credits',
          },
        },
      },
      action: CarbonLotteryAction.deposit,
      walletAddress: 'wrf123',
      amountCredits: '25',
    );

    expect(request.requestId, 'req-1');
    expect(request.action, CarbonLotteryAction.deposit);
    expect(request.walletAddress, 'wrf123');
    expect(request.amountCredits, '25');
    expect(request.status, 'submitted');
  });
}
