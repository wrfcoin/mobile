import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/achievement_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/leaderboard_entry_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/reward_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/providers/gamification_provider.dart';

// ---------------------------------------------------------------------------
// Stub repository that returns configured responses without network.
// ---------------------------------------------------------------------------

class _StubRepo extends GamificationRepository {
  _StubRepo() : super(Dio(BaseOptions()));

  Either<Failure, RewardResult>? claimResult;
  Either<Failure, List<AchievementModel>>? achievementsResult;
  int claimCallCount = 0;

  @override
  Future<Either<Failure, RewardResult>> claimReward(
    String userId,
    String achievementId,
  ) async {
    claimCallCount++;
    return claimResult ??
        Right(RewardResult(rewardId: 'r-default', wrfAmount: 1.0));
  }

  @override
  Future<Either<Failure, List<AchievementModel>>> getAchievements(
    String userId,
  ) async => achievementsResult ?? const Right([]);

  @override
  Future<Either<Failure, List<LeaderboardEntry>>> getLeaderboard() async =>
      const Right([]);

  @override
  Future<Either<Failure, List<RewardHistoryEntry>>> getRewardHistory(
    String userId,
  ) async => const Right([]);
}

// ---------------------------------------------------------------------------
// Slow stub: adds an artificial delay to simulate in-flight requests.
// ---------------------------------------------------------------------------

class _SlowStubRepo extends GamificationRepository {
  _SlowStubRepo() : super(Dio(BaseOptions()));
  final Duration delay = const Duration(milliseconds: 20);
  int claimCallCount = 0;

  @override
  Future<Either<Failure, RewardResult>> claimReward(
    String userId,
    String achievementId,
  ) async {
    claimCallCount++;
    await Future<void>.delayed(delay);
    return Right(RewardResult(rewardId: 'r', wrfAmount: 1));
  }

  @override
  Future<Either<Failure, List<AchievementModel>>> getAchievements(
    String userId,
  ) async => const Right([]);

  @override
  Future<Either<Failure, List<LeaderboardEntry>>> getLeaderboard() async =>
      const Right([]);

  @override
  Future<Either<Failure, List<RewardHistoryEntry>>> getRewardHistory(
    String userId,
  ) async => const Right([]);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GamificationNotifier.claimReward', () {
    late _StubRepo repo;
    late ProviderContainer container;
    late GamificationNotifier notifier;

    setUp(() {
      repo = _StubRepo();
      repo.claimResult = null;
      repo.achievementsResult = null;
      container = ProviderContainer(
        overrides: [gamificationRepositoryProvider.overrideWithValue(repo)],
      );
      notifier = container.read(gamificationProvider.notifier);
    });

    tearDown(() => container.dispose());

    test(
      'claiming is false and lastClaimedReward is set after success',
      () async {
        await notifier.claimReward('user-1', 'ach-1');

        expect(notifier.state.claiming, isFalse);
        expect(notifier.state.lastClaimedReward, isNotNull);
        expect(notifier.state.claimError, isNull);
      },
    );

    test('lastClaimedReward wrfAmount matches stub response', () async {
      repo.claimResult = Right(
        RewardResult(rewardId: 'r-99', wrfAmount: 12.5, txHash: '0xfeed'),
      );

      await notifier.claimReward('user-x', 'ach-x');

      final reward = notifier.state.lastClaimedReward!;
      expect(reward.wrfAmount, equals(12.5));
      expect(reward.txHash, equals('0xfeed'));
    });

    test(
      'already-claimed acknowledgement reaches state without a payout',
      () async {
        repo.claimResult = const Right(RewardResult.alreadyClaimed());

        await notifier.claimReward('user-1', 'ach-1');

        expect(notifier.state.claiming, isFalse);
        expect(notifier.state.claimError, isNull);
        final result = notifier.state.lastClaimedReward!;
        expect(result.alreadyClaimed, isTrue);
        expect(result.rewardId, isNull);
        expect(result.wrfAmount, isNull);
        expect(result.txHash, isNull);
      },
    );

    test(
      'claimError is set and lastClaimedReward is null on failure',
      () async {
        repo.claimResult = const Left(ServerFailure('Claim already processed'));

        await notifier.claimReward('user-2', 'ach-2');

        expect(notifier.state.claiming, isFalse);
        expect(notifier.state.claimError, isNotNull);
        expect(
          notifier.state.claimError!.message,
          contains('already processed'),
        );
        expect(notifier.state.lastClaimedReward, isNull);
      },
    );

    test(
      'claimError is cleared at the start of a subsequent successful claim',
      () async {
        // First claim fails.
        repo.claimResult = const Left(ServerFailure('First error'));
        await notifier.claimReward('u', 'a');
        expect(notifier.state.claimError, isNotNull);

        // Second claim succeeds.
        repo.claimResult = Right(RewardResult(rewardId: 'r', wrfAmount: 1));
        await notifier.claimReward('u', 'a');

        expect(notifier.state.claimError, isNull);
        expect(notifier.state.lastClaimedReward, isNotNull);
      },
    );

    test('concurrent claimReward calls while claiming are ignored', () async {
      final slowRepo = _SlowStubRepo();
      final slowContainer = ProviderContainer(
        overrides: [gamificationRepositoryProvider.overrideWithValue(slowRepo)],
      );
      final slowNotifier = slowContainer.read(gamificationProvider.notifier);

      // Fire two claims simultaneously.
      final f1 = slowNotifier.claimReward('u', 'a');
      final f2 = slowNotifier.claimReward('u', 'a'); // should be no-op
      await Future.wait([f1, f2]);

      expect(slowRepo.claimCallCount, equals(1));
      slowContainer.dispose();
    });
  });

  group('GamificationState.copyWith', () {
    test('claiming field updates correctly', () {
      const state = GamificationState();
      final updated = state.copyWith(claiming: true);
      expect(updated.claiming, isTrue);
      expect(updated.loading, isFalse); // untouched
    });

    test('clearClaimError sentinel sets claimError to null', () {
      const failure = ServerFailure('oops');
      const state = GamificationState(claimError: failure);
      final cleared = state.copyWith(clearClaimError: true);
      expect(cleared.claimError, isNull);
    });

    test('rewardHistory updates via copyWith', () {
      const state = GamificationState();
      final entry = RewardHistoryEntry(
        achievementId: 'a',
        wrfAmount: 5.0,
        claimedAt: DateTime(2026),
      );
      final updated = state.copyWith(rewardHistory: [entry]);
      expect(updated.rewardHistory.length, equals(1));
      expect(updated.rewardHistory.first.wrfAmount, equals(5.0));
    });
  });
}
