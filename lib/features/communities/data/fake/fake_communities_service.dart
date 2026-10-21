import 'package:fpdart/fpdart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../communities_service.dart';
import '../models/cluster_model.dart';

/// Fixture-backed [CommunitiesService] for local development and tests.
///
/// Seeds deterministic clusters on first call.  All mutations are in-memory
/// and survive the process lifetime but are not persisted to disk.
class FakeCommunitiesService implements CommunitiesService {
  FakeCommunitiesService();

  final List<ClusterModel> _clusters = <ClusterModel>[];
  bool _seeded = false;

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _ensureSeeded() {
    if (_seeded) return;
    _seeded = true;

    final now = DateTime.now();

    _clusters.addAll(<ClusterModel>[
      ClusterModel(
        id: 'cluster-fog-belt',
        name: 'Fog Belt Monitors',
        geohash: '9q8yy',
        description: 'Coastal stations tracking the marine layer from Daly City to Pacifica.',
        inviteCode: 'FOGBLT',
        createdAt: now.subtract(const Duration(days: 30)),
        members: <ClusterMember>[
          ClusterMember(
            userId: 'maya-sf',
            displayName: 'Maya',
            joinedAt: now.subtract(const Duration(days: 28)),
            stationCount: 2,
          ),
          ClusterMember(
            userId: 'reese-la',
            displayName: 'Reese',
            joinedAt: now.subtract(const Duration(days: 14)),
          ),
        ],
        messages: <ClusterMessage>[
          ClusterMessage(
            id: 'msg-fog-1',
            clusterId: 'cluster-fog-belt',
            authorId: 'maya-sf',
            authorName: 'Maya',
            content: 'Heavy advection fog this morning — visibility <50 m at my station.',
            createdAt: now.subtract(const Duration(hours: 6)),
            reactions: const <String, int>{'🌫': 4, '👍': 2},
          ),
          ClusterMessage(
            id: 'msg-fog-2',
            clusterId: 'cluster-fog-belt',
            authorId: 'reese-la',
            authorName: 'Reese',
            content: 'Same here. Temp dropped 4 °C in 20 minutes.',
            createdAt: now.subtract(const Duration(hours: 5)),
            reactions: const <String, int>{'🥶': 3},
          ),
        ],
        challenges: <ClusterChallenge>[
          ClusterChallenge(
            id: 'cc-fog-quality',
            clusterId: 'cluster-fog-belt',
            title: '7-Day Quality Blitz',
            type: ClusterChallengeType.quality,
            target: 90,
            progress: 76,
            startsAt: now.subtract(const Duration(days: 3)),
            endsAt: now.add(const Duration(days: 4)),
            status: ClusterChallengeStatus.active,
          ),
        ],
      ),
      ClusterModel(
        id: 'cluster-delta-wx',
        name: 'Delta Weather Watch',
        geohash: '9q9hp',
        description: 'Sacramento-San Joaquin Delta stations watching for Tule fog and valley heat events.',
        inviteCode: 'DELTAWX',
        createdAt: now.subtract(const Duration(days: 60)),
        members: <ClusterMember>[
          ClusterMember(
            userId: 'jordan-pdx',
            displayName: 'Jordan',
            joinedAt: now.subtract(const Duration(days: 55)),
            stationCount: 3,
          ),
        ],
        messages: <ClusterMessage>[
          ClusterMessage(
            id: 'msg-delta-1',
            clusterId: 'cluster-delta-wx',
            authorId: 'jordan-pdx',
            authorName: 'Jordan',
            content: 'NWS issued a Dense Fog Advisory. All stations reporting.',
            createdAt: now.subtract(const Duration(hours: 2)),
          ),
        ],
        challenges: <ClusterChallenge>[
          ClusterChallenge(
            id: 'cc-delta-coverage',
            clusterId: 'cluster-delta-wx',
            title: 'Full Tile Coverage',
            type: ClusterChallengeType.coverage,
            target: 1.0,
            progress: 0.7,
            startsAt: now.subtract(const Duration(days: 7)),
            endsAt: now.add(const Duration(days: 7)),
            status: ClusterChallengeStatus.active,
          ),
        ],
      ),
    ]);
  }

  ClusterModel? _findCluster(String id) {
    for (final c in _clusters) {
      if (c.id == id) return c;
    }
    return null;
  }

  int _indexOfCluster(String id) {
    for (var i = 0; i < _clusters.length; i++) {
      if (_clusters[i].id == id) return i;
    }
    return -1;
  }

  // ── CommunitiesService ────────────────────────────────────────────────────

  @override
  Future<Either<Failure, List<ClusterModel>>> getNearbyClusters({
    required String userId,
    String? geohash,
  }) async {
    _ensureSeeded();
    return Right(List<ClusterModel>.unmodifiable(_clusters));
  }

  @override
  Future<Either<Failure, List<ClusterModel>>> getMyCluster({
    required String userId,
  }) async {
    _ensureSeeded();
    final joined = _clusters
        .where((c) => c.members.any((m) => m.userId == userId))
        .toList(growable: false);
    return Right(joined);
  }

  @override
  Future<Either<Failure, ClusterModel>> joinByInviteCode({
    required String userId,
    required String displayName,
    required String inviteCode,
  }) async {
    _ensureSeeded();

    final normalised = inviteCode.trim().toUpperCase();
    if (normalised.isEmpty) {
      return const Left(ValidationFailure('Enter an invite code to join.'));
    }

    final index = _clusters.indexWhere(
      (c) => c.inviteCode.toUpperCase() == normalised,
    );
    if (index < 0) {
      return const Left(
        ValidationFailure('No cluster matched that invite code.'),
      );
    }

    final cluster = _clusters[index];
    if (cluster.members.any((m) => m.userId == userId)) {
      return const Left(
        ValidationFailure('You are already a member of this cluster.'),
      );
    }

    final newMember = ClusterMember(
      userId: userId,
      displayName: displayName,
      joinedAt: DateTime.now(),
      isCurrentUser: true,
    );

    final updated = cluster.copyWith(
      members: <ClusterMember>[...cluster.members, newMember],
      isMember: true,
    );
    _clusters[index] = updated;
    return Right(updated);
  }

  @override
  Future<Either<Failure, void>> leaveCluster({
    required String userId,
    required String clusterId,
  }) async {
    _ensureSeeded();

    final index = _indexOfCluster(clusterId);
    if (index < 0) return const Left(ValidationFailure('Cluster not found.'));

    final cluster = _clusters[index];
    final filtered = cluster.members
        .where((m) => m.userId != userId)
        .toList(growable: false);
    _clusters[index] = cluster.copyWith(members: filtered, isMember: false);
    return const Right(null);
  }

  @override
  Future<Either<Failure, List<ClusterMessage>>> getMessages({
    required String clusterId,
    int limit = 30,
  }) async {
    _ensureSeeded();

    final cluster = _findCluster(clusterId);
    if (cluster == null) return const Left(ServerFailure('Cluster not found.'));

    final msgs = cluster.messages.reversed.take(limit).toList(growable: false);
    return Right(msgs);
  }

  @override
  Future<Either<Failure, ClusterMessage>> postMessage({
    required String clusterId,
    required String authorId,
    required String authorName,
    required String content,
  }) async {
    _ensureSeeded();

    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return const Left(ValidationFailure('Message cannot be empty.'));
    }
    if (trimmed.length > 500) {
      return const Left(
        ValidationFailure('Message is too long (max 500 characters).'),
      );
    }

    final index = _indexOfCluster(clusterId);
    if (index < 0) return const Left(ServerFailure('Cluster not found.'));

    final msg = ClusterMessage(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      clusterId: clusterId,
      authorId: authorId,
      authorName: authorName,
      content: trimmed,
      createdAt: DateTime.now(),
    );

    final cluster = _clusters[index];
    _clusters[index] = cluster.copyWith(
      messages: <ClusterMessage>[...cluster.messages, msg],
    );
    return Right(msg);
  }

  @override
  Future<Either<Failure, ClusterMessage>> reactToMessage({
    required String clusterId,
    required String messageId,
    required String emoji,
  }) async {
    _ensureSeeded();

    final index = _indexOfCluster(clusterId);
    if (index < 0) return const Left(ServerFailure('Cluster not found.'));

    final cluster = _clusters[index];
    final msgIndex = cluster.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return const Left(ServerFailure('Message not found.'));

    final msg = cluster.messages[msgIndex];
    final updatedReactions = Map<String, int>.from(msg.reactions);
    updatedReactions[emoji] = (updatedReactions[emoji] ?? 0) + 1;
    final updatedMsg = msg.copyWith(reactions: updatedReactions);

    final updatedMessages = <ClusterMessage>[...cluster.messages];
    updatedMessages[msgIndex] = updatedMsg;
    _clusters[index] = cluster.copyWith(messages: updatedMessages);

    return Right(updatedMsg);
  }

  @override
  Future<Either<Failure, List<ClusterChallenge>>> getChallenges({
    required String clusterId,
  }) async {
    _ensureSeeded();

    final cluster = _findCluster(clusterId);
    if (cluster == null) return const Left(ServerFailure('Cluster not found.'));
    return Right(List<ClusterChallenge>.unmodifiable(cluster.challenges));
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final communitiesServiceProvider = Provider<CommunitiesService>((ref) {
  return FakeCommunitiesService();
});
