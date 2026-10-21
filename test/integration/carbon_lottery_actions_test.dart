import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/data/models/carbon_lottery_models.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/data/repositories/carbon_lottery_repository_impl.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/domain/repositories/carbon_lottery_repository.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/presentation/screens/carbon_lottery_dashboard_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../test_helpers/fakes.dart';

void main() {
  testWidgets('deposit and withdraw dispatch signed transaction requests', (
    tester,
  ) async {
    final repo = _RecordingCarbonLotteryRepository();
    final keyStorage = InMemoryKeyValueStorage();
    await keyStorage.write(key: 'wrf_address', value: 'wrf123');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          carbonLotteryRepositoryProvider.overrideWithValue(repo),
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: keyStorage,
            ),
          ),
          biometricServiceProvider.overrideWithValue(
            BiometricService(client: FakeLocalAuthClient()),
          ),
        ],
        child: const MaterialApp(home: CarbonLotteryDashboardScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (credits)'),
      '31',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Deposit'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(TextButton, 'Deposit'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (credits)'),
      '12',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Withdraw'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(TextButton, 'Withdraw'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.requests, [
      (CarbonLotteryAction.deposit, 'wrf123', '31'),
      (CarbonLotteryAction.withdraw, 'wrf123', '12'),
    ]);
  });
}

class _RecordingCarbonLotteryRepository implements CarbonLotteryRepository {
  final List<(CarbonLotteryAction, String, String)> requests = [];

  @override
  Future<Either<Failure, CarbonLotterySnapshot>> getDashboard({
    required String walletAddress,
  }) async {
    return Right(
      CarbonLotterySnapshot(
        epoch: 1,
        epochEndsAt: DateTime.utc(2026, 6),
        jackpotCredits: '100',
        projectedYieldCredits: '5',
        totalDepositedCredits: '1000',
        userDepositCredits: '0',
        principalProtected: true,
        preview: false,
        history: const [],
      ),
    );
  }

  @override
  Future<Either<Failure, CarbonLotteryActionRequest>> requestDeposit({
    required String walletAddress,
    required String amountCredits,
  }) async {
    requests.add((CarbonLotteryAction.deposit, walletAddress, amountCredits));
    return Right(
      CarbonLotteryActionRequest(
        requestId: 'deposit-1',
        action: CarbonLotteryAction.deposit,
        walletAddress: walletAddress,
        amountCredits: amountCredits,
        status: 'submitted',
        preview: false,
      ),
    );
  }

  @override
  Future<Either<Failure, CarbonLotteryActionRequest>> requestWithdraw({
    required String walletAddress,
    required String amountCredits,
  }) async {
    requests.add((CarbonLotteryAction.withdraw, walletAddress, amountCredits));
    return Right(
      CarbonLotteryActionRequest(
        requestId: 'withdraw-1',
        action: CarbonLotteryAction.withdraw,
        walletAddress: walletAddress,
        amountCredits: amountCredits,
        status: 'submitted',
        preview: false,
      ),
    );
  }
}
