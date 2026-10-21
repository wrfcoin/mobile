import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../data/models/carbon_lottery_models.dart';

abstract class CarbonLotteryRepository {
  Future<Either<Failure, CarbonLotterySnapshot>> getDashboard({
    required String walletAddress,
  });

  Future<Either<Failure, CarbonLotteryActionRequest>> requestDeposit({
    required String walletAddress,
    required String amountCredits,
  });

  Future<Either<Failure, CarbonLotteryActionRequest>> requestWithdraw({
    required String walletAddress,
    required String amountCredits,
  });
}
