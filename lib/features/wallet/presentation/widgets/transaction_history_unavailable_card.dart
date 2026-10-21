import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class TransactionHistoryUnavailableCard extends StatelessWidget {
  const TransactionHistoryUnavailableCard({super.key});

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.primary),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Transaction history is not available on the testnet yet',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    ),
  );
}
