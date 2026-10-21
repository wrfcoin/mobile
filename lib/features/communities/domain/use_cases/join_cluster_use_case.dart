import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../data/models/cluster_model.dart';
import '../repositories/communities_repository.dart';

/// Encapsulates the "join a cluster by invite code" workflow.
///
/// Validates inputs before delegating to the repository so the presentation
/// layer stays thin.
class JoinClusterUseCase {
  const JoinClusterUseCase(this._repository);

  final CommunitiesRepository _repository;

  Future<Either<Failure, ClusterModel>> call({
    required String userId,
    required String displayName,
    required String inviteCode,
  }) async {
    final trimmed = inviteCode.trim();
    if (trimmed.isEmpty) {
      return const Left(
        ValidationFailure('Enter an invite code to join a cluster.'),
      );
    }
    return _repository.joinByInviteCode(
      userId: userId,
      displayName: displayName,
      inviteCode: trimmed,
    );
  }
}
