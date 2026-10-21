import 'package:flutter/material.dart';

import '../../../../core/utils/wrf_units.dart';

/// Reported chain totals only: total earned is never a Network Bonus split.
class WalletRewardTotals extends StatelessWidget {
  const WalletRewardTotals({
    super.key,
    this.earnedBalanceTotal,
    this.weatherRewards,
    this.weatherRewardsPending,
    this.weatherRewardsUnavailable,
    this.onDark = false,
  });

  final String? earnedBalanceTotal;
  final String? weatherRewards;
  final String? weatherRewardsPending;
  final String? weatherRewardsUnavailable;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _amount(
          'Total earned',
          earnedBalanceTotal,
          'The node has not reported total earned.',
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _amount(
                'Weather paid',
                weatherRewards,
                weatherRewardsUnavailable ??
                    'The node has not reported paid weather rewards.',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _amount(
                'Weather pending',
                weatherRewardsPending,
                'The node has not reported pending weather rewards.',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _amount(String label, String? baseUnits, String reason) {
    final display = baseUnits == null ? null : wrfBaseUnitsToDisplay(baseUnits);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: onDark ? Colors.white70 : null),
        ),
        const SizedBox(height: 4),
        Text(
          display == null ? 'Not available' : '$display WRF',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: onDark ? Colors.white : null,
          ),
        ),
        if (display == null) ...[
          const SizedBox(height: 4),
          Text(
            reason,
            style: TextStyle(
              fontSize: 12,
              color: onDark ? Colors.white70 : null,
            ),
          ),
        ],
      ],
    );
  }
}
