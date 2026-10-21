import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../data/models/achievement_model.dart';
import '../../data/models/leaderboard_entry_model.dart';
import '../../data/models/reward_model.dart';
import '../../data/repositories/gamification_repository_impl.dart';

class GamificationState {
  final List<AchievementModel> achievements;
  final bool loading;
  final Failure? error;
  final List<LeaderboardEntry> leaderboard;
  final bool leaderboardLoading;
  final Failure? leaderboardError;

  /// True once a leaderboard read succeeded (so an empty list is genuine).
  final bool leaderboardLoaded;

  /// Whether a reward claim request is in flight.
  final bool claiming;

  /// Set when the last claim attempt failed.
  final Failure? claimError;

  /// The most recently claimed reward (cleared on next claim start).
  final RewardResult? lastClaimedReward;

  /// Reward history entries loaded via [loadRewardHistory].
  final List<RewardHistoryEntry> rewardHistory;

  const GamificationState({
    this.achievements = const [],
    this.loading = false,
    this.error,
    this.leaderboard = const [],
    this.leaderboardLoading = false,
    this.leaderboardError,
    this.leaderboardLoaded = false,
    this.claiming = false,
    this.claimError,
    this.lastClaimedReward,
    this.rewardHistory = const [],
  });

  GamificationState copyWith({
    List<AchievementModel>? achievements,
    bool? loading,
    Failure? error,
    List<LeaderboardEntry>? leaderboard,
    bool? leaderboardLoading,
    Failure? leaderboardError,
    bool? leaderboardLoaded,
    bool? claiming,
    Failure? claimError,
    RewardResult? lastClaimedReward,
    List<RewardHistoryEntry>? rewardHistory,
    // Explicit null-setters (use Object? sentinel pattern).
    bool clearClaimError = false,
    bool clearLastClaimedReward = false,
    bool clearError = false,
    bool clearLeaderboardError = false,
  }) {
    return GamificationState(
      achievements: achievements ?? this.achievements,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      leaderboard: leaderboard ?? this.leaderboard,
      leaderboardLoading: leaderboardLoading ?? this.leaderboardLoading,
      leaderboardError: clearLeaderboardError
          ? null
          : (leaderboardError ?? this.leaderboardError),
      leaderboardLoaded: leaderboardLoaded ?? this.leaderboardLoaded,
      claiming: claiming ?? this.claiming,
      claimError: clearClaimError ? null : (claimError ?? this.claimError),
      lastClaimedReward: clearLastClaimedReward
          ? null
          : (lastClaimedReward ?? this.lastClaimedReward),
      rewardHistory: rewardHistory ?? this.rewardHistory,
    );
  }
}

class GamificationNotifier extends Notifier<GamificationState> {
  late GamificationRepository _repository;

  @override
  GamificationState build() {
    _repository = ref.watch(gamificationRepositoryProvider);
    return const GamificationState();
  }

  Future<void> loadAchievements(String userId) async {
    state = state.copyWith(loading: true, clearError: true);

    final result = await _repository.getAchievements(userId);
    if (!ref.mounted) return; // notifier may have been disposed while awaiting
    result.fold(
      (failure) => state = state.copyWith(loading: false, error: failure),
      (achievements) =>
          state = state.copyWith(loading: false, achievements: achievements),
    );
  }

  Future<void> loadLeaderboard() async {
    state = state.copyWith(
      leaderboardLoading: true,
      clearLeaderboardError: true,
    );
    final result = await _repository.getLeaderboard();
    result.fold(
      // A failed read drops any stale rows: never show a partial/old board.
      (failure) => state = state.copyWith(
        leaderboardLoading: false,
        leaderboardError: failure,
        leaderboardLoaded: false,
        leaderboard: const [],
      ),
      (data) => state = state.copyWith(
        leaderboardLoading: false,
        leaderboard: data,
        leaderboardLoaded: true,
      ),
    );
  }

  /// Claims the reward for [achievementId] on behalf of [userId].
  ///
  /// Sets [GamificationState.claiming] while in flight. On success emits the
  /// [RewardResult] via [GamificationState.lastClaimedReward] and refreshes
  /// the achievement list. On failure sets [GamificationState.claimError].
  Future<void> claimReward(String userId, String achievementId) async {
    if (state.claiming) return;

    state = state.copyWith(
      claiming: true,
      clearClaimError: true,
      clearLastClaimedReward: true,
    );

    final result = await _repository.claimReward(userId, achievementId);
    result.fold(
      (failure) => state = state.copyWith(claiming: false, claimError: failure),
      (reward) {
        state = state.copyWith(
          claiming: false,
          lastClaimedReward: reward,
          clearClaimError: true,
        );
        // Refresh achievement list so claimed status updates.
        // Guard with mounted so a disposed notifier (e.g. in tests) doesn't
        // trigger a state update after disposal.
        if (ref.mounted) loadAchievements(userId);
      },
    );
  }

  /// Loads reward claim history for [userId].
  Future<void> loadRewardHistory(String userId) async {
    final result = await _repository.getRewardHistory(userId);
    result.fold(
      (_) => null, // Silently ignore errors — history is supplementary.
      (entries) => state = state.copyWith(rewardHistory: entries),
    );
  }
}

final gamificationProvider =
    NotifierProvider<GamificationNotifier, GamificationState>(
      GamificationNotifier.new,
    );
