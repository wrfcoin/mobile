import 'package:flutter/material.dart';

import '../errors/error_messages.dart';
import '../errors/failures.dart';
import '../theme/app_theme.dart';

class AppErrorWidget extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;
  final String retryLabel;

  const AppErrorWidget({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline,
    this.retryLabel = 'Retry',
  });

  factory AppErrorWidget.fromFailure(Failure failure, {VoidCallback? onRetry}) {
    final (title, icon) = switch (failure) {
      NetworkFailure() => ('Connection Issue', Icons.wifi_off),
      AuthFailure() => ('Authentication Required', Icons.lock),
      NotAvailableFailure() => ('Not Available Yet', Icons.info_outline),
      ServerFailure() => ('Something Went Wrong', Icons.cloud_off),
      CacheFailure() => ('Storage Error', Icons.storage),
      ValidationFailure() => ('Check Your Input', Icons.warning),
      SecurityFailure() => ('Connection Not Secure', Icons.shield_outlined),
    };

    return AppErrorWidget(
      title: title,
      message: ErrorMessages.fromFailure(failure),
      onRetry: onRetry,
      icon: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ],
      ),
    );
  }
}
