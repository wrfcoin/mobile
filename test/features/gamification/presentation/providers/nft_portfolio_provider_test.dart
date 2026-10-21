import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/weather_nft_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/nft_repository.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/providers/nft_portfolio_provider.dart';

import '../../../../test_helpers/fakes.dart';

const _streakNft = WeatherNftModel(
  id: 'nft-1',
  type: NftType.streak,
  tier: 'gold',
  rarity: NftRarity.rare,
  status: NftStatus.owned,
  name: '7-Day Streak',
  description: 'Collected 7 days.',
  earnedAt: '2026-04-01T00:00:00Z',
);

const _claimableNft = WeatherNftModel(
  id: 'nft-2',
  type: NftType.stormChaser,
  tier: 'platinum',
  rarity: NftRarity.legendary,
  status: NftStatus.claimable,
  name: 'Storm Chaser Elite',
  description: 'Tracked a storm.',
);

(ProviderContainer, NftPortfolioNotifier) _makeContainer(FakeNftRepository repo) {
  final container = ProviderContainer(
    overrides: [nftRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return (container, container.read(nftPortfolioProvider.notifier));
}

NftPortfolioState _state(ProviderContainer container) =>
    container.read(nftPortfolioProvider);

void main() {
  group('NftPortfolioNotifier — loadPortfolio', () {
    test('starts in initial state', () {
      final (container, _) = _makeContainer(FakeNftRepository());
      final state = _state(container);
      expect(state.nfts, isEmpty);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
    });

    test('sets loading true then resolves with nfts', () async {
      final repo = FakeNftRepository(
        portfolioResult: const Right(<WeatherNftModel>[_streakNft, _claimableNft]),
      );
      final (container, notifier) = _makeContainer(repo);

      final loadFuture = notifier.loadPortfolio('user-1');
      expect(_state(container).loading, isTrue);

      await loadFuture;

      final state = _state(container);
      expect(state.loading, isFalse);
      expect(state.nfts, hasLength(2));
      expect(state.error, isNull);
    });

    test('sets error on repository failure', () async {
      final repo = FakeNftRepository(
        portfolioResult: const Left(ServerFailure('Network down')),
      );
      final (container, notifier) = _makeContainer(repo);

      await notifier.loadPortfolio('user-1');

      final state = _state(container);
      expect(state.loading, isFalse);
      expect(state.nfts, isEmpty);
      expect(state.error, isA<ServerFailure>());
      expect(state.error!.message, 'Network down');
    });

    test('clears previous error on retry', () async {
      final repo = FakeNftRepository(
        portfolioResult: const Left(ServerFailure('Offline')),
      );
      final (container, notifier) = _makeContainer(repo);

      await notifier.loadPortfolio('user-1');
      expect(_state(container).error, isNotNull);

      repo.portfolioResult = const Right(<WeatherNftModel>[_streakNft]);
      await notifier.loadPortfolio('user-1');

      final state = _state(container);
      expect(state.error, isNull);
      expect(state.nfts, hasLength(1));
    });

    test('each loadPortfolio call hits repository once', () async {
      final repo = FakeNftRepository(
        portfolioResult: const Right(<WeatherNftModel>[_streakNft]),
      );
      final (_, notifier) = _makeContainer(repo);

      await notifier.loadPortfolio('user-1');
      await notifier.loadPortfolio('user-1');

      expect(repo.getPortfolioCalls, equals(2));
    });
  });

  group('NftPortfolioNotifier — claimNft', () {
    test('sets claiming true during claim then updates nft on success', () async {
      const claimedNft = WeatherNftModel(
        id: 'nft-2',
        type: NftType.stormChaser,
        tier: 'platinum',
        rarity: NftRarity.legendary,
        status: NftStatus.owned,
        name: 'Storm Chaser Elite',
        description: 'Tracked a storm.',
        earnedAt: '2026-04-20T00:00:00Z',
      );
      final repo = FakeNftRepository(
        portfolioResult: const Right(<WeatherNftModel>[_streakNft, _claimableNft]),
        claimResult: const Right(claimedNft),
      );
      final (container, notifier) = _makeContainer(repo);

      await notifier.loadPortfolio('user-1');

      final claimFuture = notifier.claimNft('user-1', 'nft-2');
      expect(_state(container).claiming, isTrue);

      await claimFuture;

      final state = _state(container);
      expect(state.claiming, isFalse);
      expect(state.claimError, isNull);
      final updated = state.nfts.firstWhere((n) => n.id == 'nft-2');
      expect(updated.status, NftStatus.owned);
    });

    test('sets claimError on failure', () async {
      final repo = FakeNftRepository(
        portfolioResult: const Right(<WeatherNftModel>[_claimableNft]),
        claimResult: const Left(ServerFailure('Already claimed')),
      );
      final (container, notifier) = _makeContainer(repo);

      await notifier.loadPortfolio('user-1');
      await notifier.claimNft('user-1', 'nft-2');

      final state = _state(container);
      expect(state.claiming, isFalse);
      expect(state.claimError, isA<ServerFailure>());
      expect(state.claimError!.message, 'Already claimed');
    });

    test('ignores second claim call while claiming in progress', () async {
      const claimedNft = WeatherNftModel(
        id: 'nft-2',
        type: NftType.stormChaser,
        tier: 'platinum',
        rarity: NftRarity.legendary,
        status: NftStatus.owned,
        name: 'Storm Chaser Elite',
        description: 'done',
        earnedAt: '2026-04-20T00:00:00Z',
      );
      final repo = FakeNftRepository(
        portfolioResult: const Right(<WeatherNftModel>[_claimableNft]),
        claimResult: const Right(claimedNft),
      );
      final (_, notifier) = _makeContainer(repo);

      await notifier.loadPortfolio('user-1');

      final f1 = notifier.claimNft('user-1', 'nft-2');
      final f2 = notifier.claimNft('user-1', 'nft-2');
      await Future.wait([f1, f2]);

      expect(repo.claimNftCalls, equals(1));
    });
  });
}
