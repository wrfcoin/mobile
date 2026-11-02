import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../services/api/api_client.dart';
import '../models/duel_model.dart';

final duelRepositoryProvider = Provider<DuelRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return ApiDuelRepository(client.dio, signIn: client.signInNow);
});

abstract class DuelRepository {
  Future<Either<Failure, DuelBoard>> getBoard();
  Future<Either<Failure, Duel>> getDuel(String id);
  Future<Either<Failure, Duel>> open(OpenDuelInput input);
  Future<Either<Failure, Duel>> accept(String id);
  Future<Either<Failure, Duel>> linkForecast(String id, String commitId);
  Future<Either<Failure, Duel>> handInRecord(String id, DuelRecordInput record);
}

/// The backend duel service (duel-routes.ts). Identity is the wallet: the
/// shared [ApiClient] attaches the login token and the server reads the acting
/// wallet from it, so no address is ever sent for the caller. Reads and the
/// record hand-in need no login; open, accept and link do.
class ApiDuelRepository implements DuelRepository {
  ApiDuelRepository(this._dio, {required this._signIn});

  final Dio _dio;

  /// The explicit, user-initiated wallet sign-in: returns at once with a live
  /// session, else asks for the wallet key. Called only from a user's tap.
  final Future<bool> Function() _signIn;

  /// A write is never replayed on a transient error.
  static final _write = Options(extra: {'noRetry': true});

  static const _refusals = <String, String>{
    'UNKNOWN_STATION':
        "No station has that alias. Copy it from the station's page.",
    'TOO_MANY_OPEN': 'You already have 5 unresolved duels.',
    'INVALID_TARGET': 'Pick a target hour at least 7 hours ahead.',
    'INVALID_OPPONENT': 'That opponent address is not a 0x wallet address.',
    'OWN_DUEL': 'You opened this duel; another wallet must accept it.',
    'NOT_OPEN': 'This duel already has two players.',
    'NOT_INVITED': 'This duel is for another wallet.',
    'LOCKED': 'This duel is past its lock time.',
    'NOT_ON_CHAIN':
        'The chain has no commit with this id yet. Commit your forecast first.',
    'NOT_A_FORECAST': 'That commit is not a forecast.',
    'STATION_MISMATCH': 'That forecast is for a different station.',
    'TARGET_MISMATCH': 'That forecast is for a different hour than this duel.',
    'ALREADY_LINKED': 'A forecast is already linked for you, or that forecast is used elsewhere.',
    'NOT_LINKED': 'That commit is not linked to this duel.',
    'NOT_REVEALED': 'Reveal the forecast on chain first.',
    'COMMIT_MISMATCH': 'These files do not hash to that commit id.',
    'NOT_A_PLAYER': 'Only the two players can link forecasts.',
  };

  Failure _failure(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final detail = body is Map && body['error'] is Map
        ? body['error'] as Map
        : null;
    final code = detail?['code']?.toString();
    if (status == null) return const NetworkFailure();
    if (status == 401 || code == 'WALLET_LOGIN_REQUIRED') {
      return const AuthFailure(
        'Your wallet session ended. Sign in again on the Earnings tab.',
      );
    }
    // A 404 without a code is the route being off (feature flag or edge).
    if (status == 404 && code == null) {
      return const NotAvailableFailure(
        'Forecast duels are not switched on for this network yet.',
        statusCode: 404,
      );
    }
    if (code == 'NO_SUCH_DUEL') {
      return const NotAvailableFailure('No duel has that id.', statusCode: 404);
    }
    if (status == 429) {
      return const ValidationFailure(
        'Too many requests right now. Please wait a moment and try again.',
      );
    }
    if (status >= 400 && status < 500) {
      final message = detail?['message']?.toString();
      return ValidationFailure(
        _refusals[code] ?? message ?? 'The server refused this.',
      );
    }
    return ServerFailure(
      'Duels are unavailable right now.',
      statusCode: status,
    );
  }

  Future<Either<Failure, T>> _call<T>(
    Future<Response<dynamic>> Function() request,
    T Function(Object? data) parse,
  ) async {
    try {
      final response = await request();
      return Right(parse(response.data));
    } on DioException catch (error) {
      return Left(_failure(error));
    } on FormatException {
      return const Left(
        ServerFailure('The duel service sent an unexpected answer.'),
      );
    } on TypeError {
      return const Left(
        ServerFailure('The duel service sent an unexpected answer.'),
      );
    }
  }

  Future<Either<Failure, Duel>> _asWallet(
    Future<Response<dynamic>> Function() request,
  ) async {
    if (!await _signIn()) {
      return const Left(
        AuthFailure('Sign in with your wallet to duel. Nothing was sent.'),
      );
    }
    return _call(request, Duel.fromEnvelope);
  }

  @override
  Future<Either<Failure, DuelBoard>> getBoard() =>
      _call(() => _dio.get(ApiConstants.duels), DuelBoard.fromJson);

  @override
  Future<Either<Failure, Duel>> getDuel(String id) =>
      _call(() => _dio.get(ApiConstants.duel(id)), Duel.fromEnvelope);

  @override
  Future<Either<Failure, Duel>> open(OpenDuelInput input) => _asWallet(
    () => _dio.post(ApiConstants.duels, data: input.toJson(), options: _write),
  );

  // The edge admits these writes only with a JSON body, so accept sends `{}`.
  @override
  Future<Either<Failure, Duel>> accept(String id) => _asWallet(
    () => _dio.post(
      ApiConstants.duelAccept(id),
      data: const <String, dynamic>{},
      options: _write,
    ),
  );

  @override
  Future<Either<Failure, Duel>> linkForecast(String id, String commitId) =>
      _asWallet(
        () => _dio.post(
          ApiConstants.duelForecast(id),
          data: {'commitId': commitId},
          options: _write,
        ),
      );

  @override
  Future<Either<Failure, Duel>> handInRecord(
    String id,
    DuelRecordInput record,
  ) => _call(
    () => _dio.post(
      ApiConstants.duelRecord(id),
      data: record.toJson(),
      options: _write,
    ),
    Duel.fromEnvelope,
  );
}
