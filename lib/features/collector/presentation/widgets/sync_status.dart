import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class SyncStatus extends StatelessWidget {
  final int pendingCount;

  const SyncStatus({super.key, required this.pendingCount});

  @override
  Widget build(BuildContext context) {
    if (pendingCount == 0) {
      return Semantics(
        label: 'All readings synced',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done, color: AppColors.success, size: 20),
            SizedBox(width: 4),
            Text(
              'Synced',
              style: TextStyle(color: AppColors.success, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: '$pendingCount readings pending sync',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_upload, color: AppColors.warning, size: 16),
            const SizedBox(width: 4),
            Text(
              '$pendingCount pending',
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
