import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/wrf_units.dart';
import '../../../../services/crypto/key_manager.dart';
import 'wallet_reward_totals.dart';

class BalanceCard extends StatelessWidget {
  final String address;
  final String balance;
  final String? earnedBalanceTotal;
  final String? weatherRewardsPending;
  final String? weatherRewardsUnavailable;
  final String? weatherRewards;
  final int pendingTransactions;

  const BalanceCard({
    super.key,
    required this.address,
    required this.balance,
    this.earnedBalanceTotal,
    this.weatherRewardsPending,
    this.weatherRewardsUnavailable,
    this.weatherRewards,
    this.pendingTransactions = 0,
  });

  @override
  Widget build(BuildContext context) {
    final maskedAddress = KeyManager.maskAddress(address);
    final displayBalance = wrfBaseUnitsToDisplay(balance) ?? balance;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Balance',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Tooltip(
                message: 'Copy wallet address',
                child: Semantics(
                  button: true,
                  label: 'Copy wallet address',
                  child: GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: address));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Address copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          maskedAddress,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy, size: 14, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '$displayBalance WRF',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (pendingTransactions > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$pendingTransactions processing',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          WalletRewardTotals(
            earnedBalanceTotal: earnedBalanceTotal,
            weatherRewards: weatherRewards,
            weatherRewardsPending: weatherRewardsPending,
            weatherRewardsUnavailable: weatherRewardsUnavailable,
            onDark: true,
          ),
        ],
      ),
    );
  }
}
