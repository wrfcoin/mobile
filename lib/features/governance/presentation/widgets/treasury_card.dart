import 'package:flutter/material.dart';

import '../../../../core/formatting/reported_amount.dart';
import '../../../../core/theme/app_theme.dart';

class TreasuryCard extends StatelessWidget {
  final String? balance;
  final Object? amountUnits;
  final int activeProposals;

  const TreasuryCard({
    super.key,
    this.balance,
    this.amountUnits,
    this.activeProposals = 0,
  });

  @override
  Widget build(BuildContext context) {
    final amount = declaredWrfAmount(balance, amountUnits, 'balance');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.secondary, Color(0xFF6C3DD1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DAO Treasury',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            amount ?? 'Balance unavailable',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$activeProposals active proposal${activeProposals == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
