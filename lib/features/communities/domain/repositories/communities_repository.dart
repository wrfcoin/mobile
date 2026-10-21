import 'package:fpdart/fpdart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../data/communities_service.dart';
import '../../data/fake/fake_communities_service.dart';
import '../../data/models/cluster_model.dart';

/// Domain-level repository that wraps [CommunitiesService].
///
/// Adds offline caching and any cross-cutting concerns (logging, retry) that
/// don't belong in the service layer.  Currently a thin pass-through; caching
/// is added once the real backend is wired.
abstract class CommunitiesRepository {
  Future<Either<Failure, List<ClusterModel>>> getNearbyClusters({
    required String userId,
    String? geohash,
  });

  Future<Either<Failure, List<ClusterModel>>> getMyCluster({
    required String userId,
  });

  Future<Either<Failure, ClusterModel>> joinByInviteCode({
    required String userId,
    required String displayName,
    required String inviteCode,
  });

  Future<Either<Failure, void>> leaveCluster({
    required String userId,
    required String clusterId,
  });

  Future<Either<Failure, List<ClusterMessage>>> getMessages({
    required String clusterId,
    int limit = 30,
  });

  Future<Either<Failure, ClusterMessage>> postMessage({
    required String clusterId,
    required String authorId,
    required String authorName,
    required String content,
  });

  Future<Either<Failure, ClusterMessage>> reactToMessage({
    required String clusterId,
    required String messageId,
    required String emoji,
  });

  Future<Either<Failure, List<ClusterChallenge>>> getChallenges({
    required String clusterId,
  });
}

class CommunitiesRepositoryImpl implements CommunitiesRepository {
  CommunitiesRepositoryImpl(this._service);

  final CommunitiesService _service;

  @override
  Future<Either<Failure, List<ClusterModel>>> getNearbyClusters({
    required String userId,
    String? geohash,
  }) => _service.getNearbyClusters(userId: userId, geohash: geohash);

  @override
  Future<Either<Failure, List<ClusterModel>>> getMyCluster({
    required String userId,
  }) => _service.getMyCluster(userId: userId);

  @override
  Future<Either<Failure, ClusterModel>> joinByInviteCode({
    required String userId,
    required String displayName,
    required String inviteCode,
  }) => _service.joinByInviteCode(
    userId: userId,
    displayName: displayName,
    inviteCode: inviteCode,
  );

  @override
  Future<Either<Failure, void>> leaveCluster({
    required String userId,
    required String clusterId,
  }) => _service.leaveCluster(userId: userId, clusterId: clusterId);

  @override
  Future<Either<Failure, List<ClusterMessage>>> getMessages({
    required String clusterId,
    int limit = 30,
  }) => _service.getMessages(clusterId: clusterId, limit: limit);

  @override
  Future<Either<Failure, ClusterMessage>> postMessage({
    required String clusterId,
    required String authorId,
    required String authorName,
    required String content,
  }) => _service.postMessage(
    clusterId: clusterId,
    authorId: authorId,
    authorName: authorName,
    content: content,
  );

  @override
  Future<Either<Failure, ClusterMessage>> reactToMessage({
    required String clusterId,
    required String messageId,
    required String emoji,
  }) => _service.reactToMessage(
    clusterId: clusterId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<Either<Failure, List<ClusterChallenge>>> getChallenges({
    required String clusterId,
  }) => _service.getChallenges(clusterId: clusterId);
}

final communitiesRepositoryProvider = Provider<CommunitiesRepository>((ref) {
  return CommunitiesRepositoryImpl(ref.watch(communitiesServiceProvider));
});
