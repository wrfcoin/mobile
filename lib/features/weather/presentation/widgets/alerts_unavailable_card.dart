import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Shown instead of an alerts list, or "All clear", when the alerts call
/// failed. Absence of alerts is only claimed after a successful response.
class AlertsUnavailableCard extends StatelessWidget {
  static const title = 'Alerts unavailable';

  const AlertsUnavailableCard({super.key, this.detail, this.onRetry});

  /// The failure, in user terms.
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        const Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          detail == null
              ? 'Active alerts for your area could not be checked.'
              : 'Active alerts for your area could not be checked. $detail',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ],
    );
  }
}
