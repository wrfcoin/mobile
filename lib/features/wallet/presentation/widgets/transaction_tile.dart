import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/wrf_units.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/models/transaction_model.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final VoidCallback? onTap;

  const TransactionTile({super.key, required this.transaction, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPaidReward =
        transaction.settlement == 'paid' &&
        (transaction.type == 'weather_reward' ||
            transaction.type == 'forecast_reward');
    final isTransfer =
        transaction.type.toLowerCase() == 'transfer' ||
        transaction.type == 'WRF';
    final confirmedTransfer =
        isTransfer &&
        (transaction.settlement == 'included' ||
            (transaction.eventId == null && transaction.settlement == null));
    final direction = confirmedTransfer || isPaidReward
        ? transaction.direction
        : 'unknown';
    final amount = transaction.value;
    final validAmount =
        amount != null &&
        RegExp(r'^(0|[1-9][0-9]{0,38})$').hasMatch(amount) &&
        BigInt.parse(amount) <= (BigInt.one << 128) - BigInt.one;
    final display = validAmount ? wrfBaseUnitsToDisplay(amount) : null;
    final positive = validAmount && BigInt.parse(amount) > BigInt.zero;
    final isOperation = !isTransfer && !isPaidReward;
    final (title, icon, accentColor, sign) = isOperation
        ? (
            _operationTitle(transaction.type),
            Icons.receipt_long,
            AppColors.textMuted,
            '',
          )
        : switch (direction) {
            'incoming' => (
              'Received',
              Icons.arrow_downward,
              AppColors.success,
              '+',
            ),
            'outgoing' => ('Sent', Icons.arrow_upward, AppColors.error, '-'),
            'self' => (
              'Self transfer',
              Icons.swap_vert,
              AppColors.textMuted,
              '',
            ),
            _ => ('Transaction', Icons.swap_vert, AppColors.textMuted, ''),
          };
    final String peerLine;
    if (isOperation) {
      peerLine = transaction.settlement == 'included'
          ? 'Included on chain'
          : 'Network operation';
    } else if (isPaidReward) {
      peerLine = transaction.type == 'weather_reward'
          ? 'Weather reward'
          : 'Forecast reward';
    } else if (direction == 'incoming') {
      peerLine = 'From: ${_masked(transaction.from)}';
    } else if (direction == 'outgoing') {
      peerLine = 'To: ${_masked(transaction.to)}';
    } else if (direction == 'self') {
      peerLine = 'Your own account';
    } else {
      peerLine = 'Direction not reported';
    }
    final amountText = display == null
        ? 'Amount not reported'
        : '${positive ? sign : ''}$display WRF';
    final amountColor = display != null && positive
        ? accentColor
        : AppColors.textMuted;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                semanticLabel: title,
                color: accentColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    peerLine,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isOperation)
                    Text(
                      amountText,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  if (!isOperation) const SizedBox(height: 2),
                  if (transaction.status case final status?)
                    _StatusBadge(status: status)
                  else if (transaction.blockNumber > 0)
                    Text(
                      'Block ${transaction.blockNumber}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _masked(String? address) {
  if (address == null || address.isEmpty) return 'not reported';
  return KeyManager.maskAddress(address);
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      'confirmed' => (AppColors.success, Icons.check_circle),
      'pending' => (AppColors.warning, Icons.schedule),
      'failed' => (AppColors.error, Icons.error_outline),
      _ => (AppColors.textMuted, Icons.help_outline),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(status, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

// Canonical names: core4 355ae7a3, shared-protocol/src/blockchain/transaction.rs:74-168.
// Operation names are not evidence of WRF credits, debits or zero movement.
String _operationTitle(String type) => switch (type.toLowerCase()) {
  'regular' => 'Network operation',
  'coinbase' => 'Block issuance',
  'stake' => 'Stake operation',
  'unstake' => 'Unstake operation',
  'nftcreation' => 'NFT creation',
  'nfttransfer' => 'NFT transfer',
  'nftexecution' => 'NFT execution',
  'dataanalysis' => 'Data analysis',
  'datacollection' => 'Data collection',
  'datastorage' => 'Data storage',
  'environmentaloffset' => 'Environmental offset',
  'bridgelock' => 'Bridge lock',
  'bridgeunlock' => 'Bridge unlock',
  'contributioncommit' => 'Weather data commit',
  'contributionreveal' => 'Weather data reveal',
  'forecastcommit' => 'Forecast commit',
  'forecastreveal' => 'Forecast reveal',
  'oracleattestation' => 'Oracle attestation',
  'governanceproposal' => 'Governance proposal',
  'governancevote' => 'Governance vote',
  'governanceexecute' => 'Governance execution',
  'governancefinalize' => 'Governance finalization',
  'governancedelegate' => 'Governance delegation',
  'treasurydeposit' => 'Treasury deposit',
  'treasurywithdraw' => 'Treasury withdrawal',
  'reward' => 'Reward operation',
  'confidentialtransfer' => 'Private transfer',
  'shieldeddeposit' => 'Shielded deposit',
  'shieldedwithdrawal' => 'Shielded withdrawal',
  'layer2batchsubmit' => 'Rollup batch submission',
  'rewardclaim' => 'Reward claim',
  'slashingreport' => 'Slashing report',
  'oracleregistration' => 'Oracle registration',
  'stationregistration' => 'Station registration',
  'featurescheduleextension' => 'Feature schedule extension',
  'slashevidencereport' => 'Slash evidence report',
  _ => 'Network operation',
};
