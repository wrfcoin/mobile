import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../data/repositories/gamification_repository_impl.dart';
import '../providers/gamification_provider.dart';
import '../providers/role_earnings_provider.dart';
import '../widgets/role_earnings_board.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<LeaderboardScreen> createState() =>
      _CapabilityLeaderboardState();
}

class _CapabilityLeaderboardState extends ConsumerState<LeaderboardScreen> {
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    // A Profile summary can keep the shared provider alive while navigating.
    // Re-entering this screen retries only a previously cached UNKNOWN.
    if (ref.read(earningsReadProvider).hasError) {
      Future.microtask(() {
        if (mounted) _refreshCapability();
      });
    }
  }

  Future<void> _refreshCapability() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      ref.invalidate(earningsReadProvider);
      await ref.read(earningsReadProvider.future);
    } catch (_) {
      // The provider exposes a sanitized UNKNOWN state; no background retry.
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final capability = ref.watch(earningsReadProvider);
    if (!capability.isLoading && capability.asData?.value == false) {
      return _LegacyLeaderboardScreen(embedded: widget.embedded);
    }
    final body = capability.hasError && !capability.isLoading
        ? RefreshIndicator(
            onRefresh: _refreshCapability,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(32),
              children: [
                const SizedBox(height: 64),
                const Text(
                  'Earnings unavailable right now',
                  textAlign: TextAlign.center,
                ),
                const Text(
                  'We could not confirm whether role earnings are available.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: _refreshCapability,
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        : !capability.isLoading && capability.asData?.value == true
        ? const RoleEarningsBoard()
        : const Center(child: CircularProgressIndicator());
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Leaderboard')),
            body: body,
          );
  }
}

class _LegacyLeaderboardScreen extends ConsumerStatefulWidget {
  const _LegacyLeaderboardScreen({this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<_LegacyLeaderboardScreen> createState() =>
      _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<_LegacyLeaderboardScreen> {
  @override
  void initState() {
    super.initState();
    // Provider state may not change during initState; defer to a microtask.
    Future.microtask(() {
      if (mounted) ref.read(gamificationProvider.notifier).loadLeaderboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gamificationProvider);

    final body = state.leaderboardLoading
        ? const Padding(
            padding: EdgeInsets.all(16),
            child: ShimmerList(count: 5, height: 72),
          )
        : state.leaderboardError != null
        ? _error(state.leaderboardError!)
        : state.leaderboardLoaded && state.leaderboard.isEmpty
        ? const Center(child: Text('No one has earned yet'))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.leaderboard.length,
            itemBuilder: (context, index) {
              final entry = state.leaderboard[index];
              final rank = entry.rank;
              final name = entry.name;
              final score = entry.score;
              final subtitle = entry.subtitle;
              final isTop3 = rank <= 3;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: isTop3 ? AppColors.surfaceLight : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isTop3
                        ? _medalColor(rank)
                        : AppColors.surfaceLight,
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        color: isTop3
                            ? AppColors.background
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  title: Text(name),
                  subtitle: (subtitle.isEmpty && !entry.isYou)
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entry.isYou)
                              const Text(
                                'You',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        score,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        entry.metricLabel,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: body,
    );
  }

  Widget _error(Failure failure) {
    void retry() => ref.read(gamificationProvider.notifier).loadLeaderboard();
    if (failure is NotAvailableFailure &&
        failure.detail == GamificationRepository.earningsUnavailableDetail) {
      return AppErrorWidget(
        title: 'Earnings unavailable right now',
        message: 'We could not confirm every amount, so no ranking is shown.',
        icon: Icons.hourglass_empty,
        onRetry: retry,
      );
    }
    return AppErrorWidget.fromFailure(failure, onRetry: retry);
  }

  Color _medalColor(int rank) {
    return switch (rank) {
      1 => const Color(0xFFFFD700), // Gold
      2 => const Color(0xFFC0C0C0), // Silver
      3 => const Color(0xFFCD7F32), // Bronze
      _ => AppColors.surfaceLight,
    };
  }
}
