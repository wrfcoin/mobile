enum ChallengeFormat { headToHead, team }

extension ChallengeFormatX on ChallengeFormat {
  String get label => switch (this) {
    ChallengeFormat.headToHead => 'Head-to-head',
    ChallengeFormat.team => 'Team battle',
  };
}

enum ChallengeStatus { pending, live, completed }

extension ChallengeStatusX on ChallengeStatus {
  String get label => switch (this) {
    ChallengeStatus.pending => 'Pending',
    ChallengeStatus.live => 'Live',
    ChallengeStatus.completed => 'Completed',
  };
}

class ChallengeParticipant {
  final String id;
  final String name;
  final int score;
  final bool isCurrentUser;
  final String teamName;
  final String subtitle;

  const ChallengeParticipant({
    required this.id,
    required this.name,
    required this.score,
    this.isCurrentUser = false,
    this.teamName = '',
    this.subtitle = '',
  });

  ChallengeParticipant copyWith({
    String? id,
    String? name,
    int? score,
    bool? isCurrentUser,
    String? teamName,
    String? subtitle,
  }) {
    return ChallengeParticipant(
      id: id ?? this.id,
      name: name ?? this.name,
      score: score ?? this.score,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      teamName: teamName ?? this.teamName,
      subtitle: subtitle ?? this.subtitle,
    );
  }
}

class ChallengeModel {
  final String id;
  final String title;
  final String description;
  final ChallengeFormat format;
  final ChallengeStatus status;
  final String inviteCode;
  final int targetScore;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime lastUpdatedAt;
  final String metricLabel;
  final List<ChallengeParticipant> participants;

  const ChallengeModel({
    required this.id,
    required this.title,
    required this.description,
    required this.format,
    required this.status,
    required this.inviteCode,
    required this.targetScore,
    required this.startsAt,
    required this.endsAt,
    required this.lastUpdatedAt,
    this.metricLabel = 'readings',
    this.participants = const <ChallengeParticipant>[],
  });

  bool get isLive => status == ChallengeStatus.live;

  bool get isCompleted => status == ChallengeStatus.completed;

  int get participantCount => participants.length;

  int get topScore => participants.isEmpty
      ? 0
      : participants
            .map((participant) => participant.score)
            .reduce((left, right) => left > right ? left : right);

  ChallengeParticipant? get currentUserParticipant {
    for (final participant in participants) {
      if (participant.isCurrentUser) {
        return participant;
      }
    }
    return null;
  }

  double get progress {
    if (targetScore <= 0) return 0;
    return (topScore / targetScore).clamp(0, 1).toDouble();
  }

  ChallengeModel copyWith({
    String? id,
    String? title,
    String? description,
    ChallengeFormat? format,
    ChallengeStatus? status,
    String? inviteCode,
    int? targetScore,
    DateTime? startsAt,
    DateTime? endsAt,
    DateTime? lastUpdatedAt,
    String? metricLabel,
    List<ChallengeParticipant>? participants,
  }) {
    return ChallengeModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      format: format ?? this.format,
      status: status ?? this.status,
      inviteCode: inviteCode ?? this.inviteCode,
      targetScore: targetScore ?? this.targetScore,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      metricLabel: metricLabel ?? this.metricLabel,
      participants: participants ?? this.participants,
    );
  }
}

class CreateChallengeInput {
  final String title;
  final String description;
  final ChallengeFormat format;
  final int targetScore;
  final Duration duration;

  const CreateChallengeInput({
    required this.title,
    required this.description,
    required this.format,
    required this.targetScore,
    required this.duration,
  });
}
