import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/models/cluster_model.dart';
import '../../domain/repositories/communities_repository.dart';
import '../../domain/use_cases/join_cluster_use_case.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class CommunitiesState {
  const CommunitiesState({
    this.loading = true,
    this.joining = false,
    this.posting = false,
    this.error,
    this.currentUserId,
    this.currentUserName = 'Collector',
    this.clusters = const <ClusterModel>[],
    this.selectedClusterId,
    this.locationSharingEnabled = false,
    this.userGeohash,
  });

  final bool loading;
  final bool joining;
  final bool posting;
  final Failure? error;
  final String? currentUserId;
  final String currentUserName;
  final List<ClusterModel> clusters;
  final String? selectedClusterId;

  /// Whether the user has opted in to coarse location sharing for discovery.
  final bool locationSharingEnabled;

  /// Precision-5 geohash (~1 km) of the user's opt-in location; null if sharing is off.
  final String? userGeohash;

  ClusterModel? get selectedCluster {
    if (selectedClusterId == null) {
      return clusters.isEmpty ? null : clusters.first;
    }
    for (final c in clusters) {
      if (c.id == selectedClusterId) return c;
    }
    return clusters.isEmpty ? null : clusters.first;
  }

  List<ClusterModel> get joinedClusters =>
      clusters.where((c) => c.isMember).toList(growable: false);

  CommunitiesState copyWith({
    bool? loading,
    bool? joining,
    bool? posting,
    Failure? error,
    bool clearError = false,
    String? currentUserId,
    String? currentUserName,
    List<ClusterModel>? clusters,
    String? selectedClusterId,
    bool clearSelected = false,
    bool? locationSharingEnabled,
    String? userGeohash,
    bool clearGeohash = false,
  }) {
    return CommunitiesState(
      loading: loading ?? this.loading,
      joining: joining ?? this.joining,
      posting: posting ?? this.posting,
      error: clearError ? null : (error ?? this.error),
      currentUserId: currentUserId ?? this.currentUserId,
      currentUserName: currentUserName ?? this.currentUserName,
      clusters: clusters ?? this.clusters,
      selectedClusterId: clearSelected
          ? null
          : (selectedClusterId ?? this.selectedClusterId),
      locationSharingEnabled:
          locationSharingEnabled ?? this.locationSharingEnabled,
      userGeohash: clearGeohash ? null : (userGeohash ?? this.userGeohash),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class CommunitiesNotifier extends Notifier<CommunitiesState> {
  late CommunitiesRepository _repository;
  late KeyManager _keyManager;

  @override
  CommunitiesState build() {
    _repository = ref.watch(communitiesRepositoryProvider);
    _keyManager = ref.watch(keyManagerProvider);
    unawaited(_initialize());
    return const CommunitiesState();
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

    final result = await _repository.getNearbyClusters(
      userId: address,
      geohash: state.userGeohash,
    );

    result.fold(
      (failure) => state = state.copyWith(loading: false, error: failure),
      (clusters) => _setClusters(clusters, loading: false),
    );
  }

  /// Reload nearby clusters (e.g. after enabling location sharing).
  Future<void> refresh() async {
    final userId = state.currentUserId;
    if (userId == null) return;

    state = state.copyWith(loading: true, clearError: true);
    final result = await _repository.getNearbyClusters(
      userId: userId,
      geohash: state.userGeohash,
    );

    result.fold(
      (failure) => state = state.copyWith(loading: false, error: failure),
      (clusters) => _setClusters(clusters, loading: false),
    );
  }

  /// Join a cluster by invite code.
  Future<void> joinByInviteCode(String inviteCode) async {
    final userId = state.currentUserId;
    if (userId == null) return;

    state = state.copyWith(joining: true, clearError: true);

    final useCase = JoinClusterUseCase(_repository);
    final result = await useCase(
      userId: userId,
      displayName: state.currentUserName,
      inviteCode: inviteCode,
    );

    if (!ref.mounted) return;

    result.fold(
      (failure) => state = state.copyWith(joining: false, error: failure),
      (cluster) {
        final updated = _replaceClusters(cluster);
        state = state.copyWith(
          joining: false,
          clusters: updated,
          selectedClusterId: cluster.id,
        );
      },
    );
  }

  /// Leave the current user's cluster.
  Future<void> leaveCluster(String clusterId) async {
    final userId = state.currentUserId;
    if (userId == null) return;

    final result = await _repository.leaveCluster(
      userId: userId,
      clusterId: clusterId,
    );

    if (!ref.mounted) return;

    result.fold((failure) => state = state.copyWith(error: failure), (_) {
      final updated = state.clusters
          .map((c) {
            if (c.id != clusterId) return c;
            return c.copyWith(
              isMember: false,
              members: c.members.where((m) => m.userId != userId).toList(),
            );
          })
          .toList(growable: false);
      state = state.copyWith(clusters: updated, clearSelected: true);
    });
  }

  /// Post a new message to the selected cluster's neighbourhood channel.
  Future<void> postMessage(String content) async {
    final userId = state.currentUserId;
    final cluster = state.selectedCluster;
    if (userId == null || cluster == null) return;

    state = state.copyWith(posting: true, clearError: true);

    final result = await _repository.postMessage(
      clusterId: cluster.id,
      authorId: userId,
      authorName: state.currentUserName,
      content: content,
    );

    if (!ref.mounted) return;

    result.fold(
      (failure) => state = state.copyWith(posting: false, error: failure),
      (msg) {
        final updatedCluster = cluster.copyWith(
          messages: <ClusterMessage>[...cluster.messages, msg],
        );
        state = state.copyWith(
          posting: false,
          clusters: _replaceClusters(updatedCluster),
        );
      },
    );
  }

  /// Add a reaction emoji to a message.
  Future<void> reactToMessage(String messageId, String emoji) async {
    final cluster = state.selectedCluster;
    if (cluster == null) return;

    final result = await _repository.reactToMessage(
      clusterId: cluster.id,
      messageId: messageId,
      emoji: emoji,
    );

    if (!ref.mounted) return;

    result.fold((_) {}, (updatedMsg) {
      final updatedMessages = cluster.messages
          .map((m) {
            return m.id == messageId ? updatedMsg : m;
          })
          .toList(growable: false);
      final updatedCluster = cluster.copyWith(messages: updatedMessages);
      state = state.copyWith(clusters: _replaceClusters(updatedCluster));
    });
  }

  void selectCluster(String clusterId) {
    state = state.copyWith(selectedClusterId: clusterId);
  }

  /// Toggle opt-in location sharing.  When enabled the caller should supply a
  /// precision-5 geohash; never supply raw coordinates.
  void setLocationSharing({required bool enabled, String? geohash}) {
    state = state.copyWith(
      locationSharingEnabled: enabled,
      userGeohash: enabled ? geohash : null,
      clearGeohash: !enabled,
    );
    if (enabled) unawaited(refresh());
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _setClusters(List<ClusterModel> clusters, {bool? loading}) {
    state = state.copyWith(
      loading: loading ?? state.loading,
      clusters: clusters,
    );
  }

  List<ClusterModel> _replaceClusters(ClusterModel updated) {
    final hadIt = state.clusters.any((c) => c.id == updated.id);
    if (!hadIt) return <ClusterModel>[...state.clusters, updated];
    return state.clusters
        .map((c) {
          return c.id == updated.id ? updated : c;
        })
        .toList(growable: false);
  }

  String _displayNameFor(String address) {
    final suffix = address.length <= 4
        ? address.toUpperCase()
        : address.substring(address.length - 4).toUpperCase();
    return 'Collector $suffix';
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final communitiesProvider =
    NotifierProvider<CommunitiesNotifier, CommunitiesState>(
      CommunitiesNotifier.new,
    );
