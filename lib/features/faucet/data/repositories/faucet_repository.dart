import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/dio_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../services/api/api_client.dart';
import '../datasources/faucet_remote_datasource.dart';
import '../models/faucet_models.dart';

final faucetRemoteDataSourceProvider = Provider<FaucetRemoteDataSource>((ref) {
  return FaucetRemoteDataSource(ref.watch(apiClientProvider).dio);
});

final faucetRepositoryProvider = Provider<FaucetRepository>((ref) {
  return FaucetRepository(ref.watch(faucetRemoteDataSourceProvider));
});

/// Coordinates the faucet captcha-challenge → claim flow and translates
/// backend error envelopes (`{ error: { code, message } }`) into honest
/// [Failure]s. There is no preview/fallback fast-path: failures are surfaced
/// to the UI exactly as the backend reports them.
class FaucetRepository {
  final FaucetRemoteDataSource _dataSource;

  FaucetRepository(this._dataSource);

  Future<Either<Failure, FaucetChallenge>> requestChallenge() async {
    try {
      return Right(await _dataSource.requestChallenge());
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } on StateError catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, FaucetClaimResult>> claim({
    required String walletAddress,
    required String challengeId,
    required int answer,
  }) async {
    try {
      final result = await _dataSource.claim(
        walletAddress: walletAddress,
        challengeId: challengeId,
        answer: answer,
      );
      return Right(result);
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } on StateError catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Prefers the backend's `error.message` (honest, user-actionable copy such
  /// as "already claimed within the last 24 hours") and falls back to the
  /// shared [DioErrorMapper] when no structured error is present.
  Failure _mapDioError(DioException error) {
    final backendMessage = _extractBackendMessage(error);
    final statusCode = error.response?.statusCode;
    if (backendMessage != null) {
      // 429 (ALREADY_CLAIMED / RATE_LIMITED) and 400 (INVALID_ADDRESS /
      // CAPTCHA_FAILED) carry actionable copy worth showing verbatim.
      return ServerFailure(backendMessage, statusCode: statusCode);
    }
    return DioErrorMapper.map(error);
  }

  String? _extractBackendMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map) {
        final message = err['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message;
        }
      }
      final flat = data['message'];
      if (flat is String && flat.trim().isNotEmpty) {
        return flat;
      }
    }
    return null;
  }
}
