// ── Enums ─────────────────────────────────────────────────────────────────────

enum ClusterChallengeType {
  /// Collective average data-quality score across member stations.
  quality,

  /// Collective streak of consecutive days with ≥1 reading from each member.
  streak,

  /// Geographic coverage: fraction of grid tiles with at least one reading.
  coverage,
}

extension ClusterChallengeTypeX on ClusterChallengeType {
  String get label => switch (this) {
    ClusterChallengeType.quality => 'Data Quality',
    ClusterChallengeType.streak => 'Collective Streak',
    ClusterChallengeType.coverage => 'Coverage',
  };
}

enum ClusterChallengeStatus { active, completed, failed }

extension ClusterChallengeStatusX on ClusterChallengeStatus {
  String get label => switch (this) {
    ClusterChallengeStatus.active => 'Active',
    ClusterChallengeStatus.completed => 'Completed',
    ClusterChallengeStatus.failed => 'Failed',
  };
}

// ── Models ────────────────────────────────────────────────────────────────────

/// A member of a station cluster.
class ClusterMember {
  const ClusterMember({
    required this.userId,
    required this.displayName,
    required this.joinedAt,
    this.stationCount = 1,
    this.isCurrentUser = false,
  });

  final String userId;
  final String displayName;
  final DateTime joinedAt;

  /// Number of weather stations the member operates in this cluster's tile.
  final int stationCount;

  final bool isCurrentUser;

  ClusterMember copyWith({
    String? userId,
    String? displayName,
    DateTime? joinedAt,
    int? stationCount,
    bool? isCurrentUser,
  }) {
    return ClusterMember(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      joinedAt: joinedAt ?? this.joinedAt,
      stationCount: stationCount ?? this.stationCount,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
    );
  }
}

/// A short announcement or reaction in a cluster's neighbourhood channel.
class ClusterMessage {
  const ClusterMessage({
    required this.id,
    required this.clusterId,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.reactions = const <String, int>{},
  });

  final String id;
  final String clusterId;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime createdAt;

  /// Emoji → reaction count, e.g. {'👍': 3, '🌧': 1}.
  final Map<String, int> reactions;

  ClusterMessage copyWith({
    String? id,
    String? clusterId,
    String? authorId,
    String? authorName,
    String? content,
    DateTime? createdAt,
    Map<String, int>? reactions,
  }) {
    return ClusterMessage(
      id: id ?? this.id,
      clusterId: clusterId ?? this.clusterId,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      reactions: reactions ?? this.reactions,
    );
  }
}

/// A group-level challenge that all cluster members participate in collectively.
class ClusterChallenge {
  const ClusterChallenge({
    required this.id,
    required this.clusterId,
    required this.title,
    required this.type,
    required this.target,
    required this.progress,
    required this.startsAt,
    required this.endsAt,
    required this.status,
  });

  final String id;
  final String clusterId;
  final String title;
  final ClusterChallengeType type;

  /// Target value (e.g. quality score 90, streak 7 days, coverage 0.8).
  final double target;

  /// Current collective progress toward [target].
  final double progress;

  final DateTime startsAt;
  final DateTime endsAt;
  final ClusterChallengeStatus status;

  double get progressFraction =>
      target <= 0 ? 0 : (progress / target).clamp(0.0, 1.0);

  ClusterChallenge copyWith({
    String? id,
    String? clusterId,
    String? title,
    ClusterChallengeType? type,
    double? target,
    double? progress,
    DateTime? startsAt,
    DateTime? endsAt,
    ClusterChallengeStatus? status,
  }) {
    return ClusterChallenge(
      id: id ?? this.id,
      clusterId: clusterId ?? this.clusterId,
      title: title ?? this.title,
      type: type ?? this.type,
      target: target ?? this.target,
      progress: progress ?? this.progress,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      status: status ?? this.status,
    );
  }
}

/// A geographic station cluster — the top-level community entity.
class ClusterModel {
  const ClusterModel({
    required this.id,
    required this.name,
    required this.geohash,
    required this.description,
    required this.inviteCode,
    required this.createdAt,
    this.members = const <ClusterMember>[],
    this.messages = const <ClusterMessage>[],
    this.challenges = const <ClusterChallenge>[],
    this.isMember = false,
  });

  final String id;
  final String name;

  /// Geohash at ~1 km resolution (precision 5).  Used for proximity grouping.
  /// Individual station coordinates are never stored — privacy by design.
  final String geohash;

  final String description;

  /// Short alphanumeric code used for manual cluster joins.
  final String inviteCode;

  final DateTime createdAt;
  final List<ClusterMember> members;
  final List<ClusterMessage> messages;
  final List<ClusterChallenge> challenges;

  /// True when the current user is a member of this cluster.
  final bool isMember;

  int get memberCount => members.length;

  ClusterMember? get currentUserMember {
    for (final m in members) {
      if (m.isCurrentUser) return m;
    }
    return null;
  }

  ClusterModel copyWith({
    String? id,
    String? name,
    String? geohash,
    String? description,
    String? inviteCode,
    DateTime? createdAt,
    List<ClusterMember>? members,
    List<ClusterMessage>? messages,
    List<ClusterChallenge>? challenges,
    bool? isMember,
  }) {
    return ClusterModel(
      id: id ?? this.id,
      name: name ?? this.name,
      geohash: geohash ?? this.geohash,
      description: description ?? this.description,
      inviteCode: inviteCode ?? this.inviteCode,
      createdAt: createdAt ?? this.createdAt,
      members: members ?? this.members,
      messages: messages ?? this.messages,
      challenges: challenges ?? this.challenges,
      isMember: isMember ?? this.isMember,
    );
  }
}
