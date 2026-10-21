import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/dio_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../services/api/api_client.dart';
import '../../domain/repositories/carbon_lottery_repository.dart';
import '../datasources/carbon_lottery_remote_datasource.dart';
import '../models/carbon_lottery_models.dart';

final carbonLotteryRemoteDataSourceProvider =
    Provider<CarbonLotteryRemoteDataSource>((ref) {
      return CarbonLotteryRemoteDataSource(ref.watch(apiClientProvider).dio);
    });

final carbonLotteryRepositoryProvider = Provider<CarbonLotteryRepository>((
  ref,
) {
  return CarbonLotteryRepositoryImpl(
    ref.watch(carbonLotteryRemoteDataSourceProvider),
  );
});

class CarbonLotteryRepositoryImpl implements CarbonLotteryRepository {
  final CarbonLotteryRemoteDataSource _dataSource;

  CarbonLotteryRepositoryImpl(this._dataSource);

  @override
  Future<Either<Failure, CarbonLotterySnapshot>> getDashboard({
    required String walletAddress,
  }) async {
    try {
      final dashboard = await _dataSource.getDashboard(walletAddress);
      return Right(dashboard);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } on StateError catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, CarbonLotteryActionRequest>> requestDeposit({
    required String walletAddress,
    required String amountCredits,
  }) {
    return _requestAction(
      action: CarbonLotteryAction.deposit,
      walletAddress: walletAddress,
      amountCredits: amountCredits,
    );
  }

  @override
  Future<Either<Failure, CarbonLotteryActionRequest>> requestWithdraw({
    required String walletAddress,
    required String amountCredits,
  }) {
    return _requestAction(
      action: CarbonLotteryAction.withdraw,
      walletAddress: walletAddress,
      amountCredits: amountCredits,
    );
  }

  Future<Either<Failure, CarbonLotteryActionRequest>> _requestAction({
    required CarbonLotteryAction action,
    required String walletAddress,
    required String amountCredits,
  }) async {
    try {
      final request = action == CarbonLotteryAction.deposit
          ? await _dataSource.requestDeposit(
              walletAddress: walletAddress,
              amountCredits: amountCredits,
            )
          : await _dataSource.requestWithdraw(
              walletAddress: walletAddress,
              amountCredits: amountCredits,
            );
      return Right(request);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } on StateError catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
