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

import '../../../test_helpers/fakes.dart';

void main() {
  testWidgets('dashboard renders jackpot, epoch, history, and disclosures', (
    tester,
  ) async {
    final keyStorage = InMemoryKeyValueStorage();
    await keyStorage.write(key: 'wrf_address', value: 'wrf123');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          carbonLotteryRepositoryProvider.overrideWithValue(
            _FakeCarbonLotteryRepository(),
          ),
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: keyStorage,
            ),
          ),
        ],
        child: const MaterialApp(home: CarbonLotteryDashboardScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Epoch 9'), findsOneWidget);
    expect(find.text('2048 credits'), findsOneWidget);
    expect(find.text('Recent winners and donations'), findsOneWidget);
    expect(find.textContaining('Principal safety'), findsOneWidget);
    expect(find.text('Deposit'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Winner payout'), findsOneWidget);
  });
}

class _FakeCarbonLotteryRepository implements CarbonLotteryRepository {
  @override
  Future<Either<Failure, CarbonLotterySnapshot>> getDashboard({
    required String walletAddress,
  }) async {
    return Right(
      CarbonLotterySnapshot(
        epoch: 9,
        epochEndsAt: DateTime.utc(2026, 6),
        jackpotCredits: '2048',
        projectedYieldCredits: '96',
        totalDepositedCredits: '50000',
        userDepositCredits: '75',
        principalProtected: true,
        preview: false,
        history: const [
          CarbonLotteryHistoryEntry(
            id: 'winner-1',
            epoch: 8,
            label: 'Winner payout',
            amountCredits: '64',
            walletAddress: 'wrfabc',
            timestamp: null,
            type: 'winner',
          ),
        ],
      ),
    );
  }

  @override
  Future<Either<Failure, CarbonLotteryActionRequest>> requestDeposit({
    required String walletAddress,
    required String amountCredits,
  }) async {
    return Right(
      CarbonLotteryActionRequest(
        requestId: 'synthetic-request',
        status: 'submitted',
        preview: false,
        action: CarbonLotteryAction.deposit,
        walletAddress: walletAddress,
        amountCredits: amountCredits,
      ),
    );
  }

  @override
  Future<Either<Failure, CarbonLotteryActionRequest>> requestWithdraw({
    required String walletAddress,
    required String amountCredits,
  }) async {
    return Right(
      CarbonLotteryActionRequest(
        requestId: 'synthetic-request',
        status: 'submitted',
        preview: false,
        action: CarbonLotteryAction.withdraw,
        walletAddress: walletAddress,
        amountCredits: amountCredits,
      ),
    );
  }
}
