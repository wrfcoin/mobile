import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/achievement_model.dart';

/// Displays an achievement badge with tier colour, earned/locked state, and
/// progress bar for unearned badges.
///
/// When [isNew] is `true` (badge was just unlocked), plays a scale-in
/// animation (elasticOut, 400 ms) followed by a shimmer overlay (600 ms) to
/// celebrate the unlock. Wrapped in [RepaintBoundary] so badge animation
/// repaints are isolated from parent scrolling widgets.
class AchievementBadge extends StatefulWidget {
  const AchievementBadge({
    super.key,
    required this.achievement,
    this.isNew = false,
  });

  final AchievementModel achievement;

  /// When true, plays a scale-in + shimmer celebration animation on mount.
  final bool isNew;

  @override
  State<AchievementBadge> createState() => _AchievementBadgeState();
}

class _AchievementBadgeState extends State<AchievementBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  bool _showShimmer = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    if (widget.isNew) {
      _controller.forward().then((_) {
        if (mounted) {
          setState(() => _showShimmer = true);
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) setState(() => _showShimmer = false);
          });
        }
      });
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _tierColor => switch (widget.achievement.tier.toLowerCase()) {
    'bronze' => const Color(0xFFCD7F32),
    'silver' => const Color(0xFFC0C0C0),
    'gold' => const Color(0xFFFFD700),
    'platinum' => const Color(0xFFE5E4E2),
    'diamond' => const Color(0xFFB9F2FF),
    _ => AppColors.textSecondary,
  };

  IconData get _tierIcon => switch (widget.achievement.tier.toLowerCase()) {
    'bronze' => Icons.emoji_events,
    'silver' => Icons.emoji_events,
    'gold' => Icons.emoji_events,
    'platinum' => Icons.military_tech,
    'diamond' => Icons.diamond,
    _ => Icons.stars,
  };

  @override
  Widget build(BuildContext context) {
    final achievement = widget.achievement;
    final semanticsLabel = achievement.earned
        ? '${achievement.name}, ${achievement.tier} tier, earned'
        : '${achievement.name}, ${achievement.tier} tier, '
              '${(achievement.progress * 100).round()}% complete';

    return Semantics(
      label: semanticsLabel,
      child: RepaintBoundary(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: _BadgeContent(
            achievement: achievement,
            tierColor: _tierColor,
            tierIcon: _tierIcon,
            showShimmer: _showShimmer,
          ),
        ),
      ),
    );
  }
}

class _BadgeContent extends StatelessWidget {
  const _BadgeContent({
    required this.achievement,
    required this.tierColor,
    required this.tierIcon,
    required this.showShimmer,
  });

  final AchievementModel achievement;
  final Color tierColor;
  final IconData tierIcon;
  final bool showShimmer;

  @override
  Widget build(BuildContext context) {
    final container = Container(
      width: 80,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: achievement.earned
            ? tierColor.withValues(alpha: 0.1)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: achievement.earned ? tierColor : AppColors.border,
          width: achievement.earned ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                tierIcon,
                size: 32,
                color: achievement.earned ? tierColor : AppColors.textMuted,
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Icon(
                  achievement.earned ? Icons.check_circle : Icons.lock_outline,
                  size: 16,
                  color: achievement.earned
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            achievement.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: achievement.earned
                  ? AppColors.textPrimary
                  : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          if (!achievement.earned) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: achievement.progress,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation(
                  tierColor.withValues(alpha: 0.5),
                ),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${(achievement.progress * 100).round()}%',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ] else
            Text(
              achievement.tier.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: tierColor,
              ),
            ),
        ],
      ),
    );

    if (!showShimmer) return container;

    // Shimmer overlay: runs for 600ms after the scale-in completes.
    return Shimmer.fromColors(
      baseColor: tierColor.withValues(alpha: 0.3),
      highlightColor: Colors.white.withValues(alpha: 0.8),
      child: container,
    );
  }
}
