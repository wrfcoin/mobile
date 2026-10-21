import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/dio_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../../../../services/crypto/signed_transfer.dart';
import '../datasources/wallet_remote_datasource.dart';
import '../models/wallet_model.dart';
import '../models/transaction_page.dart';

const pendingTransferMessage =
    'Previous transfer still pending; try again after it confirms';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepositoryImpl(ref.watch(walletRemoteDataSourceProvider));
});

class WalletRepositoryImpl implements WalletRepository {
  final WalletRemoteDataSource _dataSource;

  WalletRepositoryImpl(this._dataSource);

  @override
  Future<Either<Failure, WalletModel>> getWallet(String address) async {
    try {
      final wallet = await _dataSource.getWallet(address);
      return Right(wallet);
    } on StateError catch (e) {
      return Left(ServerFailure(e.message));
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, TransactionPage>> getTransactions(
    String address, {
    int offset = 0,
    int limit = 20,
    String? creditAfter,
    CancelToken? cancelToken,
  }) async {
    try {
      final transactions = await _dataSource.getTransactions(
        address,
        offset: offset,
        limit: limit,
        creditAfter: creditAfter,
        cancelToken: cancelToken,
      );
      return Right(transactions);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> sendTransaction({
    required String from,
    required String to,
    required String amountBaseUnits,
    required Ed25519TransferSigner signer,
  }) async {
    try {
      final result = await _dataSource.sendTransaction(
        from: from,
        to: to,
        amountBaseUnits: amountBaseUnits,
        signer: signer,
      );
      return Right(result);
    } on DioException catch (e) {
      // A send using the still-current account nonce conflicts while the
      // previous transfer awaits inclusion. Leave the next attempt to the user.
      if (e.response?.statusCode == 409) {
        return const Left(
          ServerFailure(pendingTransferMessage, statusCode: 409),
        );
      }
      return Left(DioErrorMapper.map(e));
    } on ArgumentError catch (e) {
      return Left(ValidationFailure(e.message.toString()));
    } on StateError catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> generateStealthAddress(
    String recipientAddress,
  ) async {
    try {
      final address = await _dataSource.generateStealthAddress(
        recipientAddress,
      );
      return Right(address);
    } on StateError catch (e) {
      return Left(ServerFailure(e.message));
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> sendPrivateTransaction({
    required String from,
    required String to,
    required String amount,
    required String privacyLevel,
    String? memo,
  }) async {
    try {
      final result = await _dataSource.sendPrivateTransaction(
        from: from,
        to: to,
        amount: amount,
        privacyLevel: privacyLevel,
        memo: memo,
      );
      return Right(result);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> estimateGas({
    required String from,
    required String to,
    required String amount,
    String? memo,
  }) async {
    try {
      final result = await _dataSource.estimateGas(
        from: from,
        to: to,
        amount: amount,
        memo: memo,
      );
      return Right(result);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> sponsorGas({
    required String walletAddress,
    required Map<String, dynamic> userOp,
  }) async {
    try {
      final result = await _dataSource.sponsorGas(
        walletAddress: walletAddress,
        userOp: userOp,
      );
      return Right(result);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> submitUserOp({
    required Map<String, dynamic> userOp,
  }) async {
    try {
      final result = await _dataSource.submitUserOp(userOp: userOp);
      return Right(result);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
