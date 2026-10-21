import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/analytics_models.dart';

class CollectionHeatmapWidget extends StatelessWidget {
  const CollectionHeatmapWidget({
    super.key,
    required this.bins,
    required this.peakCount,
  });

  final List<AnalyticsHeatmapBin> bins;
  final int peakCount;

  @override
  Widget build(BuildContext context) {
    final gridSize = bins.isEmpty
        ? 0
        : (bins.map((bin) => bin.row).reduce((a, b) => a > b ? a : b) + 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final cellSize = (width - 12) / (gridSize == 0 ? 1 : gridSize);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.05,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: bins.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridSize == 0 ? 1 : gridSize,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemBuilder: (context, index) {
                  final bin = bins[index];
                  final intensity = peakCount == 0
                      ? 0.0
                      : bin.count / peakCount;
                  final background = Color.lerp(
                    AppColors.surfaceLight.withValues(alpha: 0.22),
                    AppColors.primary,
                    intensity.clamp(0, 1),
                  )!;
                  final foreground = intensity > 0.55
                      ? AppColors.background
                      : AppColors.textPrimary;

                  return Container(
                    constraints: BoxConstraints.tightFor(
                      width: cellSize,
                      height: cellSize,
                    ),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        bin.count == 0 ? '0' : '${bin.count}',
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _LegendSwatch(
                  color: AppColors.surfaceLight.withValues(alpha: 0.22),
                  label: 'Low',
                ),
                const SizedBox(width: 12),
                _LegendSwatch(
                  color: AppColors.primary.withValues(alpha: 0.85),
                  label: 'High',
                ),
                const Spacer(),
                Text(
                  peakCount == 0
                      ? 'No dense pockets yet'
                      : 'Peak $peakCount readings',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
