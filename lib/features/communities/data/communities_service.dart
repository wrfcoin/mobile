import 'package:fpdart/fpdart.dart';

import '../../../core/errors/failures.dart';
import 'models/cluster_model.dart';

/// Abstract backend interface for the Local Communities feature.
///
/// The real HTTP implementation will be added in a future round once the
/// backend endpoints exist.  Until then, [FakeCommunitiesService] is wired
/// in as the provider value.
abstract class CommunitiesService {
  /// Return clusters near the caller.  [geohash] is a precision-5 geohash
  /// (~1 km tile) for the user's opt-in location; pass null when location
  /// sharing is disabled.
  Future<Either<Failure, List<ClusterModel>>> getNearbyClusters({
    required String userId,
    String? geohash,
  });

  /// Return all clusters the current user has joined.
  Future<Either<Failure, List<ClusterModel>>> getMyCluster({
    required String userId,
  });

  /// Join a cluster via its invite code.
  Future<Either<Failure, ClusterModel>> joinByInviteCode({
    required String userId,
    required String displayName,
    required String inviteCode,
  });

  /// Leave a cluster.
  Future<Either<Failure, void>> leaveCluster({
    required String userId,
    required String clusterId,
  });

  /// Fetch messages for a cluster (most recent first).
  Future<Either<Failure, List<ClusterMessage>>> getMessages({
    required String clusterId,
    int limit = 30,
  });

  /// Post a new message to the neighbourhood channel.
  Future<Either<Failure, ClusterMessage>> postMessage({
    required String clusterId,
    required String authorId,
    required String authorName,
    required String content,
  });

  /// Add or increment a reaction on a message.
  Future<Either<Failure, ClusterMessage>> reactToMessage({
    required String clusterId,
    required String messageId,
    required String emoji,
  });

  /// Fetch active group challenges for a cluster.
  Future<Either<Failure, List<ClusterChallenge>>> getChallenges({
    required String clusterId,
  });
}
