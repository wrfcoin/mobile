import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/feature_flags/feature_flags.dart';
import '../../../../services/api/api_client.dart';
import '../models/challenge_model.dart';

class ChallengeCapability {
  final bool available;
  final String reason;

  const ChallengeCapability({required this.available, required this.reason});

  static const unavailable = ChallengeCapability(
    available: false,
    reason: 'Friend Challenges are unavailable until a persistent challenge service is connected.',
  );
}

/// Release capability gate: the backend challenge service (backend#249,
/// `/api/challenges`) behind [FeatureFlags.enableFriendChallenges]. With the
/// flag off the screen stays on its "unavailable" state and nothing is sent.
final challengeCapabilityProvider = Provider<ChallengeCapability>((ref) {
  final enabled = ref.watch(
    featureFlagsProvider.select((flags) => flags.enableFriendChallenges),
  );
  return enabled
      ? const ChallengeCapability(
          available: true,
          reason: 'Points only: counts are readings from your stations that landed on chain.',
        )
      : ChallengeCapability.unavailable;
});

final challengeRepositoryProvider = Provider<ChallengeRepository>((ref) {
  final enabled = ref.watch(
    featureFlagsProvider.select((flags) => flags.enableFriendChallenges),
  );
  if (!enabled) return const UnavailableChallengeRepository();
  return ApiChallengeRepository(ref.watch(apiClientProvider).dio);
});

abstract class ChallengeRepository {
  Future<Either<Failure, List<ChallengeModel>>> getChallenges({
    required String userId,
    required String displayName,
  });

  Future<Either<Failure, List<ChallengeModel>>> createChallenge({
    required String userId,
    required String displayName,
    required CreateChallengeInput input,
  });

  Future<Either<Failure, List<ChallengeModel>>> joinChallengeByReferralCode({
    required String userId,
    required String displayName,
    required String referralCode,
  });

  Future<Either<Failure, List<ChallengeModel>>> registerCollection({
    required String userId,
    required int delta,
  });
}

class UnavailableChallengeRepository implements ChallengeRepository {
  const UnavailableChallengeRepository();

  static const _failure = ServerFailure(
    'Friend Challenges require a persistent challenge service.',
    statusCode: 503,
  );

  @override
  Future<Either<Failure, List<ChallengeModel>>> getChallenges({
    required String userId,
    required String displayName,
  }) async => const Left(_failure);

  @override
  Future<Either<Failure, List<ChallengeModel>>> createChallenge({
    required String userId,
    required String displayName,
    required CreateChallengeInput input,
  }) async => const Left(_failure);

  @override
  Future<Either<Failure, List<ChallengeModel>>> joinChallengeByReferralCode({
    required String userId,
    required String displayName,
    required String referralCode,
  }) async => const Left(_failure);

  @override
  Future<Either<Failure, List<ChallengeModel>>> registerCollection({
    required String userId,
    required int delta,
  }) async => const Left(_failure);
}

/// The backend friend challenge service (backend#249 challenge-routes.ts).
///
/// Identity is the wallet: the shared [ApiClient] attaches the wallet login
/// token, and the server reads the acting wallet from it (`userId` and
/// `displayName` are never sent). Points only. A participant's count is the
/// server's: readings from stations the wallet owns that landed on chain, so
/// [registerCollection] ignores the local delta and fetches the latest counts.
class ApiChallengeRepository implements ChallengeRepository {
  ApiChallengeRepository(this._dio);

  final Dio _dio;

  static const _messages = <String, String>{
    'NO_SUCH_CODE': 'No challenge matched that referral code.',
    'ALREADY_JOINED': 'You already joined this friend challenge.',
    'CHALLENGE_FULL': 'This challenge is already full.',
    'CHALLENGE_ENDED': 'This challenge has ended.',
    'TOO_MANY_ACTIVE': 'You already run 5 challenges. Finish one first.',
    'INVALID_CODE': 'An invite code looks like ABCD-2345.',
    'INVALID_TITLE': 'Give the challenge a title of up to 60 characters.',
  };

  Future<Either<Failure, List<ChallengeModel>>> _call(
    String userId,
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      return Right(ChallengeJson.list(response.data, currentUserId: userId));
    } on DioException catch (error) {
      return Left(_failure(error));
    } on FormatException {
      return const Left(
        ServerFailure('The challenge service sent an unexpected answer.'),
      );
    }
  }

  Failure _failure(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final code = body is Map && body['error'] is Map
        ? (body['error'] as Map)['code']?.toString()
        : null;
    if (status == 401 || status == 403) {
      return const AuthFailure('Sign in with your wallet to use challenges.');
    }
    if (status == 404 && code == null) {
      return const NotAvailableFailure(
        'Friend Challenges are not switched on for this network yet.',
        statusCode: 404,
      );
    }
    if (status != null && status >= 400 && status < 500) {
      return ValidationFailure(
        _messages[code] ?? 'The challenge service refused this request.',
      );
    }
    if (status == null) return const NetworkFailure();
    return ServerFailure(
      'Friend Challenges are unavailable right now.',
      statusCode: status,
    );
  }

  @override
  Future<Either<Failure, List<ChallengeModel>>> getChallenges({
    required String userId,
    required String displayName,
  }) => _call(userId, () => _dio.get(ApiConstants.challenges));

  @override
  Future<Either<Failure, List<ChallengeModel>>> createChallenge({
    required String userId,
    required String displayName,
    required CreateChallengeInput input,
  }) {
    final hours = input.duration.inHours.clamp(1, 30 * 24);
    return _call(
      userId,
      () => _dio.post(
        ApiConstants.challenges,
        // A create is not idempotent: never replay it on a retry.
        options: Options(extra: {'noRetry': true}),
        data: {
          'title': input.title.trim(),
          'description': input.description.trim(),
          'format': input.format == ChallengeFormat.team
              ? 'team'
              : 'headToHead',
          'targetScore': input.targetScore,
          'durationHours': hours,
        },
      ),
    );
  }

  @override
  Future<Either<Failure, List<ChallengeModel>>> joinChallengeByReferralCode({
    required String userId,
    required String displayName,
    required String referralCode,
  }) {
    final code = referralCode.trim().toUpperCase();
    if (code.isEmpty) {
      return Future.value(
        const Left(
          ValidationFailure('Enter a referral code to join a challenge.'),
        ),
      );
    }
    return _call(
      userId,
      () => _dio.post(ApiConstants.challengesJoin, data: {'inviteCode': code}),
    );
  }

  @override
  Future<Either<Failure, List<ChallengeModel>>> registerCollection({
    required String userId,
    required int delta,
  }) => _call(userId, () => _dio.post(ApiConstants.challengesSync, data: {}));
}
