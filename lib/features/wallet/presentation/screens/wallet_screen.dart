import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_handoff.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/feature_flags/build_flags.dart';
import '../../../../core/feature_flags/feature_flags.dart';
import '../../../../core/formatting/app_formatters.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/wrf_units.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/crypto/collect_key_store.dart';
import '../../../collector/data/services/station_registration_service.dart';
import '../../../../services/crypto/wallet_secure_storage.dart';
import '../../data/models/transaction_model.dart';
import '../providers/transactions_provider.dart';
import '../widgets/transaction_history_unavailable_card.dart';
import '../providers/wallet_provider.dart';
import '../providers/wallet_security_provider.dart';
import '../widgets/auth_handoff_banner.dart';
import '../widgets/balance_card.dart';
import '../widgets/testnet_notice.dart';
import '../widgets/not_signed_in_card.dart';
import '../widgets/transaction_tile.dart';

const String _notReported = 'Not reported';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final txAsync = ref.watch(transactionsProvider);
    final backupAsync = ref.watch(backupConfirmedProvider);
    final preferences = ref.watch(appPreferencesProvider).preferences;
    final authHandoff = ref.watch(authHandoffControllerProvider);
    final flags = ref.watch(featureFlagsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        actions: [
          if (flags.enableAnalyticsDashboard)
            Semantics(
              button: true,
              label: 'Open analytics dashboard',
              child: IconButton(
                tooltip: 'Analytics',
                icon: const Icon(Icons.insights_outlined),
                onPressed: () => context.push('/wallet/analytics'),
              ),
            ),
          Semantics(
            button: true,
            label: 'Open chain explorer',
            child: IconButton(
              tooltip: 'Chain',
              icon: const Icon(Icons.link),
              onPressed: () => context.push('/wallet/chain'),
            ),
          ),
          Semantics(
            button: true,
            label: 'Open receive screen',
            child: IconButton(
              tooltip: 'Receive WRF',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => context.push('/wallet/receive'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: TestnetNotice()),
      body: walletAsync.when(
        loading: () => const SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loading wallet balances and recent activity...',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                SizedBox(height: 16),
                ShimmerList(count: 3, height: 100),
              ],
            ),
          ),
        ),
        // A 401 here means no session, which for a wallet that never signed
        // in is not "Session expired" (mobile#320): offer Sign in instead of
        // a Retry that cannot sign in.
        error: (e, _) => e is AuthFailure
            ? _NotSignedInView(detail: authHandoff.message)
            : AppErrorWidget.fromFailure(
                e is Failure ? e : ServerFailure(e.toString()),
                onRetry: () => ref.invalidate(walletProvider),
              ),
        data: (wallet) {
          // The wallet exists but has no session: the provider stops before
          // the request and the handoff says why.
          if (wallet == null && authHandoff.offersSignIn) {
            return _NotSignedInView(detail: authHandoff.message);
          }
          if (wallet == null) {
            return ResponsiveCenter(
              maxContentWidth: 520,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (authHandoff.message != null) ...[
                    AuthHandoffBanner(handoff: authHandoff),
                    const SizedBox(height: 12),
                  ],
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Wallet Found',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create or import a wallet to get started',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/wallet/create'),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Wallet'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/wallet/import'),
                      icon: const Icon(Icons.download),
                      label: const Text('Import / Restore Wallet'),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(walletProvider.notifier).refresh();
              await ref.read(transactionsProvider.notifier).refresh();
            },
            child: ResponsiveListView(
              maxContentWidth: 960,
              children: [
                if (authHandoff.message != null) ...[
                  AuthHandoffBanner(handoff: authHandoff),
                  const SizedBox(height: 12),
                ],
                BalanceCard(
                  address: wallet.address,
                  balance: wallet.balance,
                  earnedBalanceTotal: wallet.earnedBalanceTotal,
                  weatherRewardsPending: wallet.weatherRewardsPending,
                  weatherRewardsUnavailable: wallet.weatherRewardsUnavailable,
                  weatherRewards: wallet.weatherRewards,
                  pendingTransactions: wallet.pendingTransactions,
                ),
                const SizedBox(height: 12),
                backupAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (confirmed) {
                    if (confirmed) return const SizedBox.shrink();
                    return _BackupReminderCard(
                      onConfirm: () => ref
                          .read(backupConfirmedProvider.notifier)
                          .setConfirmed(true),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // Hidden in tester (profile) builds; see WalletSendGate.
                    if (ref.watch(walletSendEnabledProvider)) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => context.push('/wallet/send'),
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text('Send'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/wallet/receive'),
                        icon: const Icon(Icons.arrow_downward),
                        label: const Text('Receive'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/wallet/faucet'),
                    icon: const Icon(Icons.water_drop_outlined),
                    label: const Text('Get Testnet Tokens'),
                  ),
                ),
                // Dark-launched until a backend exists (mobile#268).
                if (ref.watch(featureFlagsProvider).enableCarbonLottery) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/wallet/lottery'),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: const Text('Carbon Lottery'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmEmergencyWipe(context, ref),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Emergency Wipe'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${wallet.transactions} total',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                txAsync.when(
                  loading: () => const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Loading transactions...',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      SizedBox(height: 12),
                      ShimmerList(count: 2, height: 60),
                    ],
                  ),
                  error: (e, _) => e is AuthFailure
                      ? NotSignedInCard(detail: authHandoff.message)
                      : AppErrorWidget.fromFailure(
                          e is Failure ? e : ServerFailure(e.toString()),
                        ),
                  data: (txState) {
                    if (txState.historyUnavailable) {
                      return const TransactionHistoryUnavailableCard();
                    }
                    return Column(
                      children: [
                        if (txState.discoveringCredits)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text('Checking earnings history…'),
                          ),
                        if (txState.items.isEmpty && _unrepeatedCredits(txState).isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No activity in this page'),
                          ),
                        if (txState.complete == false)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              txState.windowStartHeight == null
                                  ? 'Showing recent activity only'
                                  : 'Showing activity since block '
                                        '${txState.windowStartHeight}',
                              key: const Key('wallet-history-window'),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        for (final (index, tx) in txState.items.indexed)
                          TransactionTile(
                            key: ValueKey(
                              tx.eventId ??
                                  (tx.hash.isNotEmpty
                                      ? tx.hash
                                      : 'transaction:${tx.type}:$index'),
                            ),
                            transaction: tx,
                            onTap: () => _showTransactionDetails(
                              context,
                              preferences,
                              tx,
                            ),
                          ),
                        if (_unrepeatedCredits(txState).isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Paid rewards',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Text(
                            'Reward payment dates are unavailable',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          for (final (index, tx) in _unrepeatedCredits(txState).indexed)
                            TransactionTile(
                              key: ValueKey(
                                tx.eventId ??
                                    (tx.hash.isNotEmpty
                                        ? tx.hash
                                        : 'credit:${tx.type}:$index'),
                              ),
                              transaction: tx,
                            ),
                        ],
                        if (txState.hasMore) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed:
                                  txState.loadingMore ||
                                      txState.discoveringCredits
                                  ? null
                                  : () => ref
                                        .read(transactionsProvider.notifier)
                                        .loadMore(),
                              child: txState.loadingMore
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Load more'),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTransactionDetails(
    BuildContext context,
    AppPreferences preferences,
    TransactionModel tx,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Activity Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _detailRow('From', tx.from.isEmpty ? _notReported : tx.from),
              _detailRow('To', tx.to ?? _notReported),
              _detailRow(
                'Amount',
                tx.value == null
                    ? _notReported
                    : '${wrfBaseUnitsToDisplay(tx.value!) ?? tx.value} WRF',
              ),
              if (tx.fee.isNotEmpty && tx.fee != '0')
                _detailRow(
                  'Network fee',
                  '${wrfBaseUnitsToDisplay(tx.fee) ?? tx.fee} WRF',
                ),
              _detailRow('Memo', tx.memo.isEmpty ? '-' : tx.memo),
              _detailRow('Status', tx.status ?? _notReported),
              _detailRow(
                'Timestamp',
                tx.timestamp == null
                    ? _notReported
                    : AppFormatters.formatIsoTimestamp(
                        context,
                        preferences,
                        tx.timestamp!,
                      ),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Technical Details',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                children: [
                  _detailRow('Hash', tx.hash),
                  _detailRow('Block', tx.blockNumber.toString()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEmergencyWipe(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final shouldWipe =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            final confirmationController = TextEditingController();
            var canConfirm = false;

            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Emergency wipe'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This will erase the collect key, weather-station registration, wallet, recovery metadata, address book, and active session data from this device.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmationController,
                        decoration: const InputDecoration(
                          labelText: 'Type WIPE to confirm',
                        ),
                        onChanged: (value) {
                          setState(() {
                            canConfirm = value.trim().toUpperCase() == 'WIPE';
                          });
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: canConfirm
                          ? () => Navigator.of(dialogContext).pop(true)
                          : null,
                      child: const Text('Wipe now'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    if (!shouldWipe) return;

    // Stop before touching wallet data if the collect namespace cannot be
    // erased. Keeping the wallet lets the user retry the failed wipe.
    try {
      await ref.read(collectKeyWiperProvider).wipe();
    } catch (_) {
      if (!context.mounted) return;
      AppSnackbars.error(
        context,
        const SecurityFailure(
          'Emergency wipe stopped: the collect key could not be erased. Wallet data was kept; try again.',
        ),
      );
      return;
    }

    try {
      final cleared = await ref
          .read(sharedPreferencesProvider)
          .remove(StationRegistrationService.registeredStationKey);
      if (!cleared) throw StateError('Registration cleanup failed');
      // Keep the address/metadata until key deletion succeeds: a failed
      // key wipe must not leave a private key without its wallet address.
      await ref.read(keyManagerProvider).deleteAll();
      await ref.read(walletSecureStorageProvider).clearWalletData();
    } catch (_) {
      if (!context.mounted) return;
      AppSnackbars.error(
        context,
        const SecurityFailure(
          'Emergency wipe incomplete: the collect key was erased, but wallet cleanup did not finish. Try again.',
        ),
      );
      return;
    }

    ref.invalidate(walletProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(backupConfirmedProvider);
    ref.invalidate(addressBookProvider);
    ref.invalidate(socialWalletProvider);
    ref.read(authHandoffControllerProvider).clear();

    if (!context.mounted) return;
    AppSnackbars.success(context, 'Wallet wiped from this device');
    context.go('/wallet');
  }
}

class _BackupReminderCard extends StatelessWidget {
  final VoidCallback onConfirm;

  const _BackupReminderCard({required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Backup reminder',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Confirm your recovery phrase is safely backed up.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onConfirm,
                  child: const Text('I backed it up'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotSignedInView extends StatelessWidget {
  const _NotSignedInView({this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      maxContentWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [NotSignedInCard(detail: detail)],
        ),
      ),
    );
  }
}

/// Credit rows whose eventId is not already rendered in the main list, so
/// one reward never shows twice, even when its two copies arrive on
/// different pages.
List<TransactionModel> _unrepeatedCredits(TransactionsState state) {
  final shown = {
    for (final tx in state.items)
      if (tx.eventId != null) tx.eventId!,
  };
  return [
    for (final tx in state.credits)
      if (tx.eventId == null || !shown.contains(tx.eventId)) tx,
  ];
}
