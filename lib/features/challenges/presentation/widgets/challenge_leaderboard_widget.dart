import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/challenge_model.dart';

class ChallengeLeaderboardWidget extends StatelessWidget {
  const ChallengeLeaderboardWidget({
    super.key,
    required this.challenge,
    this.compact = false,
  });

  final ChallengeModel challenge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final entries = challenge.format == ChallengeFormat.team
        ? _buildTeamEntries(challenge)
        : _buildPlayerEntries(challenge);
    final visibleEntries = compact && entries.length > 3
        ? entries.take(3).toList(growable: false)
        : entries;
    final topScore = entries.isEmpty ? 0 : entries.first.score;
    final targetScore = challenge.targetScore;
    final progress = targetScore == 0
        ? 0.0
        : (topScore / targetScore).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.leaderboard, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                compact ? challenge.title : 'Live Leaderboard',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor(challenge.status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                challenge.status.label,
                style: TextStyle(
                  color: _statusColor(challenge.status),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          Text(
            challenge.description,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: compact ? 8 : 10,
            value: progress,
            backgroundColor: AppColors.surfaceLight,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$topScore / $targetScore ${challenge.metricLabel}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ...visibleEntries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LeaderboardRow(entry: entry, compact: compact),
          );
        }),
        if (compact && entries.length > visibleEntries.length)
          Text(
            '+${entries.length - visibleEntries.length} more competitors',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  List<_LeaderboardEntry> _buildPlayerEntries(ChallengeModel challenge) {
    final orderedParticipants = <ChallengeParticipant>[
      ...challenge.participants,
    ]..sort((left, right) => right.score.compareTo(left.score));

    return orderedParticipants
        .asMap()
        .entries
        .map((entry) {
          final participant = entry.value;
          return _LeaderboardEntry(
            rank: entry.key + 1,
            label: participant.name,
            subtitle: participant.subtitle,
            score: participant.score,
            isCurrentUser: participant.isCurrentUser,
          );
        })
        .toList(growable: false);
  }

  List<_LeaderboardEntry> _buildTeamEntries(ChallengeModel challenge) {
    final teams = <String, _TeamAggregate>{};
    for (final participant in challenge.participants) {
      final teamName = participant.teamName.isEmpty
          ? 'Independent'
          : participant.teamName;
      teams.update(
        teamName,
        (aggregate) => aggregate.copyWith(
          score: aggregate.score + participant.score,
          memberCount: aggregate.memberCount + 1,
          hasCurrentUser: aggregate.hasCurrentUser || participant.isCurrentUser,
        ),
        ifAbsent: () => _TeamAggregate(
          name: teamName,
          score: participant.score,
          memberCount: 1,
          hasCurrentUser: participant.isCurrentUser,
        ),
      );
    }

    final orderedTeams = teams.values.toList(growable: false)
      ..sort((left, right) => right.score.compareTo(left.score));

    return orderedTeams
        .asMap()
        .entries
        .map((entry) {
          final team = entry.value;
          return _LeaderboardEntry(
            rank: entry.key + 1,
            label: team.name,
            subtitle: '${team.memberCount} members',
            score: team.score,
            isCurrentUser: team.hasCurrentUser,
          );
        })
        .toList(growable: false);
  }

  Color _statusColor(ChallengeStatus status) {
    return switch (status) {
      ChallengeStatus.pending => AppColors.warning,
      ChallengeStatus.live => AppColors.success,
      ChallengeStatus.completed => AppColors.primary,
    };
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.compact});

  final _LeaderboardEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: entry.isCurrentUser
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.isCurrentUser
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: compact ? 16 : 18,
            backgroundColor: _rankColor(entry.rank),
            child: Text(
              '#${entry.rank}',
              style: const TextStyle(
                color: AppColors.background,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isCurrentUser ? '${entry.label} (You)' : entry.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (entry.subtitle.isNotEmpty)
                  Text(
                    entry.subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${entry.score}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Color _rankColor(int rank) {
    return switch (rank) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => AppColors.lightBorder,
    };
  }
}

class _LeaderboardEntry {
  const _LeaderboardEntry({
    required this.rank,
    required this.label,
    required this.subtitle,
    required this.score,
    required this.isCurrentUser,
  });

  final int rank;
  final String label;
  final String subtitle;
  final int score;
  final bool isCurrentUser;
}

class _TeamAggregate {
  const _TeamAggregate({
    required this.name,
    required this.score,
    required this.memberCount,
    required this.hasCurrentUser,
  });

  final String name;
  final int score;
  final int memberCount;
  final bool hasCurrentUser;

  _TeamAggregate copyWith({
    String? name,
    int? score,
    int? memberCount,
    bool? hasCurrentUser,
  }) {
    return _TeamAggregate(
      name: name ?? this.name,
      score: score ?? this.score,
      memberCount: memberCount ?? this.memberCount,
      hasCurrentUser: hasCurrentUser ?? this.hasCurrentUser,
    );
  }
}
