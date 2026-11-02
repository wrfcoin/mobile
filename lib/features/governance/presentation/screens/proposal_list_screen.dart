import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../settings/presentation/widgets/settings_gear_button.dart';
import '../../data/repositories/governance_repository_impl.dart';
import '../providers/proposals_provider.dart';
import '../widgets/proposal_card.dart';
import '../widgets/treasury_card.dart';

class ProposalListScreen extends ConsumerStatefulWidget {
  const ProposalListScreen({super.key});

  @override
  ConsumerState<ProposalListScreen> createState() => _ProposalListScreenState();
}

class _ProposalListScreenState extends ConsumerState<ProposalListScreen> {
  String? _treasuryBalance;
  Object? _treasuryAmountUnits;

  @override
  void initState() {
    super.initState();
    _loadTreasury();
  }

  Future<void> _loadTreasury() async {
    final repo = ref.read(governanceRepositoryProvider);
    final result = await repo.getTreasuryInfo();
    result.fold(
      (_) {
        if (mounted) setState(() => _treasuryBalance = null);
      },
      (data) {
        if (mounted) {
          setState(() {
            _treasuryBalance = data['balance'] is String
                ? data['balance'] as String
                : null;
            _treasuryAmountUnits = data['amountUnits'];
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final proposalsAsync = ref.watch(proposalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Governance'),
        actions: const [SettingsGearButton()],
      ),
      body: proposalsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: ShimmerList(count: 4, height: 100),
        ),
        error: (e, _) => AppErrorWidget.fromFailure(
          e is Failure ? e : ServerFailure(e.toString()),
          onRetry: () => ref.invalidate(proposalsProvider),
        ),
        data: (proposals) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(proposalsProvider);
            await _loadTreasury();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TreasuryCard(
                balance: _treasuryBalance,
                amountUnits: _treasuryAmountUnits,
                activeProposals: proposals.length,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Proposals',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${proposals.length} total',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (proposals.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No proposals yet',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ...proposals.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ProposalCard(
                      proposal: p,
                      onTap: () => context.push('/govern/proposal', extra: p),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
