import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../data/models/carbon_lottery_models.dart';
import '../providers/carbon_lottery_provider.dart';

class CarbonLotteryDashboardScreen extends ConsumerStatefulWidget {
  const CarbonLotteryDashboardScreen({super.key});

  @override
  ConsumerState<CarbonLotteryDashboardScreen> createState() =>
      _CarbonLotteryDashboardScreenState();
}

class _CarbonLotteryDashboardScreenState
    extends ConsumerState<CarbonLotteryDashboardScreen> {
  final _amountController = TextEditingController(text: '25');
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit(CarbonLotteryAction action) async {
    final amount = _amountController.text.trim();
    final parsed = double.tryParse(amount);
    if (parsed == null || parsed <= 0) {
      AppSnackbars.error(
        context,
        const ValidationFailure('Enter a positive credit amount'),
      );
      return;
    }

    final label = action == CarbonLotteryAction.deposit
        ? 'Deposit'
        : 'Withdraw';
    final confirmed = await showConfirmDialog(
      context,
      title: '$label carbon lottery credits',
      message:
          '$label $amount credits?\nYour request will be sent to the lottery service.',
      confirmLabel: label,
    );
    if (!confirmed) return;

    setState(() => _submitting = true);
    try {
      final request = await ref
          .read(carbonLotteryProvider.notifier)
          .requestAction(action: action, amountCredits: amount);
      if (!mounted) return;
      AppSnackbars.success(
        context,
        '$label request sent',
        detail: 'Request ${request.requestId}',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbars.error(
        context,
        e is Failure ? e : ServerFailure(e.toString()),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(carbonLotteryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Carbon Lottery')),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorWidget.fromFailure(
          error is Failure ? error : ServerFailure(error.toString()),
          onRetry: () => ref.invalidate(carbonLotteryProvider),
        ),
        data: (snapshot) => RefreshIndicator(
          onRefresh: () => ref.read(carbonLotteryProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _EpochCard(snapshot: snapshot),
              const SizedBox(height: 12),
              _ActionPanel(
                amountController: _amountController,
                submitting: _submitting,
                onDeposit: () => _submit(CarbonLotteryAction.deposit),
                onWithdraw: () => _submit(CarbonLotteryAction.withdraw),
              ),
              const SizedBox(height: 12),
              _DisclosureCard(principalProtected: snapshot.principalProtected),
              const SizedBox(height: 16),
              const Text(
                'Recent winners and donations',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (snapshot.history.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No draw history yet',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ...snapshot.history.map(_HistoryTile.new),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpochCard extends StatelessWidget {
  final CarbonLotterySnapshot snapshot;

  const _EpochCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final endsAt = snapshot.epochEndsAt;
    final countdown = endsAt == null
        ? 'Epoch close pending'
        : 'Ends ${MaterialLocalizations.of(context).formatMediumDate(endsAt.toLocal())}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Epoch ${snapshot.epoch}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              countdown,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricChip(
                  label: 'Jackpot',
                  value: '${snapshot.jackpotCredits} credits',
                  icon: Icons.emoji_events_outlined,
                ),
                _MetricChip(
                  label: 'Projected yield',
                  value: '${snapshot.projectedYieldCredits} credits',
                  icon: Icons.trending_up,
                ),
                _MetricChip(
                  label: 'Pool',
                  value: '${snapshot.totalDepositedCredits} credits',
                  icon: Icons.savings_outlined,
                ),
                _MetricChip(
                  label: 'Your deposit',
                  value: '${snapshot.userDepositCredits} credits',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  final TextEditingController amountController;
  final bool submitting;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  const _ActionPanel({
    required this.amountController,
    required this.submitting,
    required this.onDeposit,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manage position',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (credits)',
                hintText: '0.00',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: submitting ? null : onDeposit,
                    icon: const Icon(Icons.add),
                    label: const Text('Deposit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: submitting ? null : onWithdraw,
                    icon: const Icon(Icons.remove),
                    label: const Text('Withdraw'),
                  ),
                ),
              ],
            ),
            if (submitting) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _DisclosureCard extends StatelessWidget {
  final bool principalProtected;

  const _DisclosureCard({required this.principalProtected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            principalProtected
                ? Icons.verified_user_outlined
                : Icons.warning_amber_outlined,
            color: principalProtected ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Principal safety: deposits remain withdrawable. Jackpot rewards depend on epoch yield and contract execution, so participation still carries smart-contract and timing risk.',
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final CarbonLotteryHistoryEntry entry;

  const _HistoryTile(this.entry);

  @override
  Widget build(BuildContext context) {
    final icon = entry.type.toLowerCase().contains('donation')
        ? Icons.volunteer_activism_outlined
        : Icons.emoji_events_outlined;

    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(entry.label),
      subtitle: Text('Epoch ${entry.epoch} - ${entry.walletAddress}'),
      trailing: Text(
        '${entry.amountCredits} credits',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
