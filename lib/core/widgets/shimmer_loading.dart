import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

class ShimmerCard extends StatelessWidget {
  final double height;

  const ShimmerCard({super.key, this.height = 80});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceLight,
      highlightColor: AppColors.surface,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class ShimmerList extends StatelessWidget {
  final int count;
  final double height;

  const ShimmerList({super.key, this.count = 3, this.height = 80});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index < count - 1 ? 8 : 0),
          child: ShimmerCard(height: height),
        );
      }),
    );
  }
}
