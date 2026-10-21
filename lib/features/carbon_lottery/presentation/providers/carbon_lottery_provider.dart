import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../services/auth/biometric_service.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/models/carbon_lottery_models.dart';
import '../../data/repositories/carbon_lottery_repository_impl.dart';

final carbonLotteryProvider =
    AsyncNotifierProvider<CarbonLotteryNotifier, CarbonLotterySnapshot>(
      CarbonLotteryNotifier.new,
      retry: (retryCount, error) => null,
    );

class CarbonLotteryNotifier extends AsyncNotifier<CarbonLotterySnapshot> {
  @override
  Future<CarbonLotterySnapshot> build() async {
    final walletAddress = await ref.watch(keyManagerProvider).getAddress();
    if (walletAddress == null) {
      throw const AuthFailure('Create or import a wallet to join the lottery');
    }

    final repo = ref.watch(carbonLotteryRepositoryProvider);
    final result = await repo.getDashboard(walletAddress: walletAddress);
    return result.fold((failure) => throw failure, (snapshot) => snapshot);
  }

  Future<CarbonLotteryActionRequest> requestAction({
    required CarbonLotteryAction action,
    required String amountCredits,
  }) async {
    final walletAddress = await ref.read(keyManagerProvider).getAddress();
    if (walletAddress == null) {
      throw const AuthFailure('Create or import a wallet to join the lottery');
    }

    final authenticated = await ref
        .read(biometricServiceProvider)
        .authenticate(reason: 'Authorize carbon lottery request');
    if (!authenticated) {
      throw const AuthFailure('Authentication required to submit request');
    }

    final repo = ref.read(carbonLotteryRepositoryProvider);
    final result = action == CarbonLotteryAction.deposit
        ? await repo.requestDeposit(
            walletAddress: walletAddress,
            amountCredits: amountCredits,
          )
        : await repo.requestWithdraw(
            walletAddress: walletAddress,
            amountCredits: amountCredits,
          );

    final request = result.fold((failure) => throw failure, (value) => value);
    await refresh();
    return request;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
