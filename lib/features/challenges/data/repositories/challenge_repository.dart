import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
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

/// Release capability gate. Tests may override this alongside an injected
/// repository, but production remains unavailable until a canonical service
/// implementation replaces this default.
final challengeCapabilityProvider = Provider<ChallengeCapability>((ref) {
  return ChallengeCapability.unavailable;
});

final challengeRepositoryProvider = Provider<ChallengeRepository>((ref) {
  return const UnavailableChallengeRepository();
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
