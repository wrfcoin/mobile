import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../data/models/weather_nft_model.dart';
import '../providers/nft_portfolio_provider.dart';

/// NFT portfolio section shown on the Profile / Achievements screen.
///
/// Renders streak and storm-chaser badges with tier, rarity, and status.
/// Uses text-only badges (no external assets) — real asset pipeline is a
/// follow-up task.
class NftPortfolioSection extends ConsumerWidget {
  const NftPortfolioSection({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nftPortfolioProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            'NFT Badges',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (state.loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ShimmerList(count: 2, height: 80),
          )
        else if (state.error != null && state.nfts.isEmpty)
          _ErrorView(
            message: state.error!.message,
            onRetry: () =>
                ref.read(nftPortfolioProvider.notifier).loadPortfolio(userId),
          )
        else if (state.nfts.isEmpty)
          const _EmptyView()
        else
          _NftGrid(
            nfts: state.nfts,
            claiming: state.claiming,
            claimError: state.claimError?.message,
            onClaim: (nftId) =>
                ref.read(nftPortfolioProvider.notifier).claimNft(userId, nftId),
          ),
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Icon(Icons.badge, size: 48, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'No NFT badges yet',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Earn streak or storm-chaser badges to see them here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(color: AppColors.error, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _NftGrid extends StatelessWidget {
  const _NftGrid({
    required this.nfts,
    required this.claiming,
    required this.claimError,
    required this.onClaim,
  });

  final List<WeatherNftModel> nfts;
  final bool claiming;
  final String? claimError;
  final void Function(String nftId) onClaim;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (claimError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              claimError!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemCount: nfts.length,
          itemBuilder: (context, index) {
            final nft = nfts[index];
            return _NftBadgeTile(
              nft: nft,
              claiming: claiming,
              onClaim: nft.isClaimable ? () => onClaim(nft.id) : null,
            );
          },
        ),
      ],
    );
  }
}

class _NftBadgeTile extends StatelessWidget {
  const _NftBadgeTile({
    required this.nft,
    required this.claiming,
    required this.onClaim,
  });

  final WeatherNftModel nft;
  final bool claiming;
  final VoidCallback? onClaim;

  Color get _tierColor => switch (nft.tier.toLowerCase()) {
    'bronze' => const Color(0xFFCD7F32),
    'silver' => const Color(0xFFC0C0C0),
    'gold' => const Color(0xFFFFD700),
    'platinum' => const Color(0xFFE5E4E2),
    _ => AppColors.textSecondary,
  };

  IconData get _typeIcon => nft.type == NftType.stormChaser
      ? Icons.thunderstorm
      : Icons.local_fire_department;

  String get _rarityLabel => switch (nft.rarity) {
    NftRarity.common => 'Common',
    NftRarity.rare => 'Rare',
    NftRarity.epic => 'Epic',
    NftRarity.legendary => 'Legendary',
  };

  @override
  Widget build(BuildContext context) {
    final isOwned = nft.isOwned;
    final isClaimable = nft.isClaimable;
    final isLocked = nft.status == NftStatus.locked;

    return Semantics(
      label:
          '${nft.name}, ${nft.tier} tier, $_rarityLabel, '
          '${isOwned
              ? "owned"
              : isClaimable
              ? "claimable"
              : "locked"}',
      child: Container(
        decoration: BoxDecoration(
          color: isOwned || isClaimable
              ? _tierColor.withValues(alpha: 0.1)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOwned || isClaimable ? _tierColor : AppColors.border,
            width: isOwned ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  _typeIcon,
                  size: 28,
                  color: isLocked ? AppColors.textMuted : _tierColor,
                ),
                if (isLocked)
                  const Positioned(
                    right: -4,
                    bottom: -4,
                    child: Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (isOwned)
                  const Positioned(
                    right: -4,
                    bottom: -4,
                    child: Icon(
                      Icons.check_circle,
                      size: 14,
                      color: AppColors.success,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              nft.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isLocked ? AppColors.textMuted : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _rarityLabel,
              style: TextStyle(
                fontSize: 10,
                color: isLocked ? AppColors.textMuted : _tierColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isClaimable) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(color: _tierColor),
                    foregroundColor: _tierColor,
                    textStyle: const TextStyle(fontSize: 10),
                  ),
                  onPressed: claiming ? null : onClaim,
                  child: claiming
                      ? const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Text('Claim'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
