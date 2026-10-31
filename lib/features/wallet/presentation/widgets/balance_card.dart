import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/models/wallet_model.dart';

/// Balance and total earned from the public balance read. Both are shown only
/// as reported: a switched-off read is `Unavailable`, a rate-limited one
/// `Busy`, and a missing total is `Unavailable`, never zero.
class BalanceCard extends StatelessWidget {
  final String address;
  final String? balance;
  final BalanceAvailability balanceAvailability;
  final String? earnedBalanceTotal;
  final int pendingTransactions;

  const BalanceCard({
    super.key,
    required this.address,
    required this.balance,
    this.balanceAvailability = BalanceAvailability.reported,
    this.earnedBalanceTotal,
    this.pendingTransactions = 0,
  });

  @override
  Widget build(BuildContext context) {
    final maskedAddress = KeyManager.maskAddress(address);
    final displayBalance = walletBalanceText(balance, balanceAvailability);
    final displayEarned = walletBalanceText(
      earnedBalanceTotal,
      balanceAvailability,
    );

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
              const Flexible(
                child: Text(
                  'Your Balance',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Tooltip(
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
                          Flexible(
                            child: Text(
                              maskedAddress,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.copy,
                            size: 14,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  displayBalance,
                  key: const Key('balance-card-balance'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Earned in total',
                      textAlign: TextAlign.end,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayEarned,
                      key: const Key('balance-card-earned'),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pendingTransactions > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$pendingTransactions processing',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Test coins have no value.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
