import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../features/collector/presentation/providers/collector_provider.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/models/challenge_model.dart';
import '../../data/repositories/challenge_repository.dart';

class ChallengesState {
  final bool loading;
  final bool creating;
  final bool joining;
  final Failure? error;
  final String? currentUserId;
  final String currentUserName;
  final List<ChallengeModel> challenges;
  final String? selectedChallengeId;
  final DateTime? lastSyncedAt;

  const ChallengesState({
    this.loading = true,
    this.creating = false,
    this.joining = false,
    this.error,
    this.currentUserId,
    this.currentUserName = 'Collector',
    this.challenges = const <ChallengeModel>[],
    this.selectedChallengeId,
    this.lastSyncedAt,
  });

  ChallengeModel? get selectedChallenge {
    if (selectedChallengeId == null) {
      return challenges.isEmpty ? null : challenges.first;
    }

    for (final challenge in challenges) {
      if (challenge.id == selectedChallengeId) {
        return challenge;
      }
    }
    return challenges.isEmpty ? null : challenges.first;
  }

  List<ChallengeModel> get joinedChallenges {
    return challenges
        .where(
          (challenge) => challenge.participants.any(
            (participant) => participant.isCurrentUser,
          ),
        )
        .toList(growable: false);
  }

  ChallengesState copyWith({
    bool? loading,
    bool? creating,
    bool? joining,
    Failure? error,
    bool clearError = false,
    String? currentUserId,
    String? currentUserName,
    List<ChallengeModel>? challenges,
    String? selectedChallengeId,
    DateTime? lastSyncedAt,
  }) {
    return ChallengesState(
      loading: loading ?? this.loading,
      creating: creating ?? this.creating,
      joining: joining ?? this.joining,
      error: clearError ? null : (error ?? this.error),
      currentUserId: currentUserId ?? this.currentUserId,
      currentUserName: currentUserName ?? this.currentUserName,
      challenges: challenges ?? this.challenges,
      selectedChallengeId: selectedChallengeId ?? this.selectedChallengeId,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class ChallengesNotifier extends Notifier<ChallengesState> {
  late ChallengeRepository _repository;
  late KeyManager _keyManager;

  @override
  ChallengesState build() {
    _repository = ref.watch(challengeRepositoryProvider);
    _keyManager = ref.watch(keyManagerProvider);
    unawaited(_initialize());
    ref.listen<CollectorState>(collectorProvider, (previous, next) {
      syncCollectorProgress(previous, next);
    });
    return const ChallengesState();
  }

  Future<void> _initialize() async {
    final address = await _keyManager.getAddress() ?? 'guest-collector';
    final displayName = _displayNameFor(address);

    state = state.copyWith(
      loading: true,
      clearError: true,
      currentUserId: address,
      currentUserName: displayName,
    );

    final result = await _repository.getChallenges(
      userId: address,
      displayName: displayName,
    );

    result.fold(
      (failure) => state = state.copyWith(loading: false, error: failure),
      (challenges) => _setChallenges(challenges, loading: false),
    );
  }

  Future<void> createChallenge(CreateChallengeInput input) async {
    final userId = state.currentUserId;
    if (userId == null) return;

    state = state.copyWith(creating: true, clearError: true);
    final result = await _repository.createChallenge(
      userId: userId,
      displayName: state.currentUserName,
      input: input,
    );

    result.fold(
      (failure) => state = state.copyWith(creating: false, error: failure),
      (challenges) => _setChallenges(challenges, creating: false),
    );
  }

  Future<void> joinByReferralCode(String referralCode) async {
    final userId = state.currentUserId;
    if (userId == null) return;

    state = state.copyWith(joining: true, clearError: true);
    final result = await _repository.joinChallengeByReferralCode(
      userId: userId,
      displayName: state.currentUserName,
      referralCode: referralCode,
    );

    result.fold(
      (failure) => state = state.copyWith(joining: false, error: failure),
      (challenges) => _setChallenges(challenges, joining: false),
    );
  }

  Future<void> registerCollectionDelta(int delta) async {
    final userId = state.currentUserId;
    if (userId == null || delta <= 0) return;

    final result = await _repository.registerCollection(
      userId: userId,
      delta: delta,
    );
    result.fold((_) {}, (challenges) => _setChallenges(challenges));
  }

  void syncCollectorProgress(CollectorState? previous, CollectorState next) {
    final previousReading = previous?.currentReading?.timestamp;
    final nextReading = next.currentReading?.timestamp;
    if (nextReading == null) return;

    final isNewReading =
        previousReading == null || nextReading.isAfter(previousReading);
    if (!isNewReading) return;

    unawaited(registerCollectionDelta(1));
  }

  void selectChallenge(String challengeId) {
    state = state.copyWith(selectedChallengeId: challengeId);
  }

  void _setChallenges(
    List<ChallengeModel> challenges, {
    bool? loading,
    bool? creating,
    bool? joining,
  }) {
    final sortedChallenges = <ChallengeModel>[...challenges]
      ..sort((left, right) {
        final statusWeight = _statusPriority(left.status)
            .compareTo(_statusPriority(right.status));
        if (statusWeight != 0) return statusWeight;
        return right.lastUpdatedAt.compareTo(left.lastUpdatedAt);
      });

    final selectedChallengeId = state.selectedChallengeId;
    final hasSelected =
        selectedChallengeId != null &&
        sortedChallenges.any(
          (challenge) => challenge.id == selectedChallengeId,
        );
    final nextSelectedId = hasSelected
        ? selectedChallengeId
        : sortedChallenges.isEmpty
        ? null
        : sortedChallenges.first.id;

    state = state.copyWith(
      loading: loading ?? state.loading,
      creating: creating ?? state.creating,
      joining: joining ?? state.joining,
      clearError: true,
      challenges: sortedChallenges,
      selectedChallengeId: nextSelectedId,
      lastSyncedAt: DateTime.now(),
    );
  }

  int _statusPriority(ChallengeStatus status) {
    return switch (status) {
      ChallengeStatus.live => 0,
      ChallengeStatus.pending => 1,
      ChallengeStatus.completed => 2,
    };
  }

  String _displayNameFor(String address) {
    final suffix = address.length <= 4
        ? address.toUpperCase()
        : address.substring(address.length - 4).toUpperCase();
    return 'Collector $suffix';
  }
}

final challengesProvider =
    NotifierProvider<ChallengesNotifier, ChallengesState>(
      ChallengesNotifier.new,
    );
