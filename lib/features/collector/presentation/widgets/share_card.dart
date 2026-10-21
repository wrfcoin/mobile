import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/station_profile_provider.dart';

/// A branded station card that can be rendered to an image and shared.
///
/// Wrap content in a [RepaintBoundary] keyed by [repaintKey] and call
/// [ShareCardHelper.shareStationCard] to capture and share.
class ShareCard extends StatelessWidget {
  final StationProfile profile;
  final GlobalKey repaintKey;

  const ShareCard({super.key, required this.profile, required this.repaintKey});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1117), Color(0xFF161B22), Color(0xFF0D1117)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with logo
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.cloud,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'WRFCoin Weather Station',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Station name
            Text(
              profile.name,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              profile.model,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ShareStat(
                  value: '${profile.uptimePercent.toStringAsFixed(1)}%',
                  label: 'Uptime',
                  color: AppColors.success,
                ),
                _ShareStat(
                  value: _formatReadings(profile.totalReadings),
                  label: 'Readings',
                  color: AppColors.primary,
                ),
                _ShareStat(
                  value: 'Top ${profile.contributorPercentile}%',
                  label: 'Rank',
                  color: AppColors.secondary,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Current conditions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (profile.recentReadings.isNotEmpty) ...[
                    _ConditionChip(
                      icon: Icons.thermostat,
                      value:
                          '${profile.recentReadings.last.temperature.toStringAsFixed(1)}°C',
                    ),
                    _ConditionChip(
                      icon: Icons.water_drop,
                      value: '${profile.recentReadings.last.humidity}%',
                    ),
                    _ConditionChip(
                      icon: Icons.speed,
                      value:
                          '${profile.recentReadings.last.pressure.toStringAsFixed(0)} hPa',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Footer
            const Text(
              'Contributing to decentralized weather data',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatReadings(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

class _ShareStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _ShareStat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _ConditionChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _ConditionChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Helper to capture the [RepaintBoundary] and share as an image.
class ShareCardHelper {
  static Future<void> shareStationCard(GlobalKey repaintKey) async {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final bytes = byteData.buffer.asUint8List();

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
            name: 'station-card.png',
          ),
        ],
        text: 'Check out my WRFCoin weather station! Contributing to decentralized weather data.',
      ),
    );
  }
}
