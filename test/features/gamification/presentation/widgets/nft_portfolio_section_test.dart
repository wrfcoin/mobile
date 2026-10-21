import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/weather_nft_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/nft_repository.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/providers/nft_portfolio_provider.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/widgets/nft_portfolio_section.dart';

import '../../../../test_helpers/fakes.dart';

// ── Notifier pre-seeded with a fixed state ─────────────────────────────────

class _FixedNftPortfolioNotifier extends NftPortfolioNotifier {
  _FixedNftPortfolioNotifier(this._initial);
  final NftPortfolioState _initial;
  @override
  NftPortfolioState build() {
    super.build();
    return _initial;
  }
}

// ── Helper ─────────────────────────────────────────────────────────────────

Widget _buildSection({
  required NftPortfolioState initialState,
  NftRepository? repository,
}) {
  return ProviderScope(
    overrides: [
      nftRepositoryProvider.overrideWithValue(
        repository ?? FakeNftRepository(),
      ),
      if (repository == null)
        nftPortfolioProvider.overrideWith(
          () => _FixedNftPortfolioNotifier(initialState),
        ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: NftPortfolioSection(userId: 'user-test'),
      ),
    ),
  );
}

// ── Fixtures ────────────────────────────────────────────────────────────────

const _streakNft = WeatherNftModel(
  id: 'nft-streak',
  type: NftType.streak,
  tier: 'gold',
  rarity: NftRarity.rare,
  status: NftStatus.owned,
  name: '7-Day Streak',
  description: 'Collected 7 days in a row.',
  earnedAt: '2026-04-01T12:00:00Z',
);

const _stormNft = WeatherNftModel(
  id: 'nft-storm',
  type: NftType.stormChaser,
  tier: 'platinum',
  rarity: NftRarity.legendary,
  status: NftStatus.claimable,
  name: 'Storm Chaser Elite',
  description: 'Tracked a Category-3 storm.',
);

const _lockedNft = WeatherNftModel(
  id: 'nft-locked',
  type: NftType.streak,
  tier: 'bronze',
  rarity: NftRarity.common,
  status: NftStatus.locked,
  name: 'First Steps',
  description: 'Collect your first reading.',
);

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('NftPortfolioSection — render', () {
    testWidgets('shows section header', (tester) async {
      await tester.pumpWidget(
        _buildSection(initialState: const NftPortfolioState()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('NFT Badges'), findsOneWidget);
    });

    testWidgets('shows empty state when no NFTs', (tester) async {
      await tester.pumpWidget(
        _buildSection(initialState: const NftPortfolioState()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No NFT badges yet'), findsOneWidget);
    });

    testWidgets('renders streak badge with fire icon and owned check', (tester) async {
      await tester.pumpWidget(
        _buildSection(
          initialState: const NftPortfolioState(nfts: [_streakNft]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('7-Day Streak'), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Rare'), findsOneWidget);
    });

    testWidgets('renders storm-chaser badge with thunderstorm icon', (tester) async {
      await tester.pumpWidget(
        _buildSection(
          initialState: const NftPortfolioState(nfts: [_stormNft]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Storm Chaser Elite'), findsOneWidget);
      expect(find.byIcon(Icons.thunderstorm), findsOneWidget);
      expect(find.text('Legendary'), findsOneWidget);
    });

    testWidgets('renders mixed owned, claimable, and locked badges', (tester) async {
      await tester.pumpWidget(
        _buildSection(
          initialState: const NftPortfolioState(
            nfts: [_streakNft, _stormNft, _lockedNft],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('7-Day Streak'), findsOneWidget);
      expect(find.text('Storm Chaser Elite'), findsOneWidget);
      expect(find.text('First Steps'), findsOneWidget);
      // Only claimable badge shows Claim button.
      expect(find.text('Claim'), findsOneWidget);
      // Owned badge shows check icon, locked badge shows lock icon.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('shows shimmer when loading', (tester) async {
      await tester.pumpWidget(
        _buildSection(
          initialState: const NftPortfolioState(loading: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No NFT badges yet'), findsNothing);
      // Grid not rendered while loading.
      expect(find.text('Claim'), findsNothing);
    });

    testWidgets('shows error message when error and no NFTs', (tester) async {
      await tester.pumpWidget(
        _buildSection(
          initialState: NftPortfolioState(
            error: const ServerFailure('Network error'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Network error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('NftPortfolioSection — claim happy-path', () {
    testWidgets('tapping Claim shows claiming spinner then success', (tester) async {
      final fakeRepo = FakeNftRepository(
        portfolioResult: const Right(<WeatherNftModel>[_stormNft]),
        claimResult: const Right(
          WeatherNftModel(
            id: 'nft-storm',
            type: NftType.stormChaser,
            tier: 'platinum',
            rarity: NftRarity.legendary,
            status: NftStatus.owned,
            name: 'Storm Chaser Elite',
            description: 'Tracked a Category-3 storm.',
            earnedAt: '2026-04-20T00:00:00Z',
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nftRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NftPortfolioSection(userId: 'user-test'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Pre-seed with claimable NFT by reading and triggering load.
      final element = tester.element(find.byType(NftPortfolioSection));
      final container = ProviderScope.containerOf(element);
      await container
          .read(nftPortfolioProvider.notifier)
          .loadPortfolio('user-test');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Claim'), findsOneWidget);

      // Tap Claim and let the fake repository resolve. The fake is
      // synchronous-ish so we don't assert on the transient spinner.
      await tester.tap(find.text('Claim'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // After claim success, Claim button disappears (badge is now owned).
      expect(find.text('Claim'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('claim error shows error message above grid', (tester) async {
      const claimErr = ServerFailure('Claim failed: already minted');
      final fakeRepo = FakeNftRepository(
        portfolioResult: const Right(<WeatherNftModel>[_stormNft]),
        claimResult: const Left(claimErr),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [nftRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(
              body: NftPortfolioSection(userId: 'user-test'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final element = tester.element(find.byType(NftPortfolioSection));
      final container = ProviderScope.containerOf(element);
      await container
          .read(nftPortfolioProvider.notifier)
          .loadPortfolio('user-test');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Claim'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Claim failed: already minted'), findsOneWidget);
    });
  });

  group('NftPortfolioSection — refresh', () {
    testWidgets('retry button triggers portfolio reload', (tester) async {
      final fakeRepo = FakeNftRepository(
        portfolioResult: const Left(ServerFailure('Offline')),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [nftRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(
              body: NftPortfolioSection(userId: 'user-test'),
            ),
          ),
        ),
      );

      final element = tester.element(find.byType(NftPortfolioSection));
      final container = ProviderScope.containerOf(element);

      // First load fails.
      await container
          .read(nftPortfolioProvider.notifier)
          .loadPortfolio('user-test');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Fix the repo and tap Retry.
      fakeRepo.portfolioResult =
          const Right(<WeatherNftModel>[_streakNft]);

      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('7-Day Streak'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);
    });

    testWidgets('loadPortfolio increments call count on FakeNftRepository', (tester) async {
      final fakeRepo = FakeNftRepository(
        portfolioResult: const Right(<WeatherNftModel>[_streakNft]),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [nftRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(
            home: Scaffold(
              body: NftPortfolioSection(userId: 'user-test'),
            ),
          ),
        ),
      );

      final element = tester.element(find.byType(NftPortfolioSection));
      final container = ProviderScope.containerOf(element);

      await container
          .read(nftPortfolioProvider.notifier)
          .loadPortfolio('user-test');
      await tester.pump(const Duration(milliseconds: 100));

      await container
          .read(nftPortfolioProvider.notifier)
          .loadPortfolio('user-test');
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeRepo.getPortfolioCalls, equals(2));
      expect(find.text('7-Day Streak'), findsOneWidget);
    });
  });
}
