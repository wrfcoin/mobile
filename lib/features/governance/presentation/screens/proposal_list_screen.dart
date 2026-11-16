import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../settings/presentation/widgets/settings_gear_button.dart';
import '../providers/proposals_provider.dart';
import '../widgets/advisory_proposal_card.dart';

/// The governance tab: chain 888's advisory proposals.
class ProposalListScreen extends ConsumerWidget {
  const ProposalListScreen({super.key, this.leading});

  /// The app bar's back button, when opened by a link with nothing to pop to.
  final Widget? leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(advisoryProposalsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: leading,
        title: const Text('Governance'),
        actions: const [SettingsGearButton()],
      ),
      body: listAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: ShimmerList(count: 4, height: 100),
        ),
        error: (e, _) => AppErrorWidget.fromFailure(
          e is Failure
              ? e
              : const ServerFailure("Couldn't load governance proposals."),
          onRetry: () => ref.invalidate(advisoryProposalsProvider),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(advisoryProposalsProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Advisory proposals',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (list.featureActive || list.proposals.isNotEmpty)
                    Text(
                      '${list.total ?? list.proposals.length} total',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Text proposals signed by testnet wallets. A passed proposal '
                'is only recorded: nothing it says is carried out. Each wallet '
                'that held at least 1 WRF when it was proposed gets one vote, '
                'so results count wallets, not people.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (list.incomplete)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Some proposals couldn't be loaded. Pull down to try again.",
                    style: TextStyle(color: AppColors.warning, fontSize: 13),
                  ),
                ),
              if (list.proposals.isEmpty)
                _EmptyState(featureActive: list.featureActive)
              else
                ...list.proposals.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AdvisoryProposalCard(
                      proposal: p,
                      observedAtHeight: list.observedAtHeight,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.featureActive});

  final bool featureActive;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          featureActive
              ? 'No advisory proposals yet. Proposals are made with the '
                    'WRFCoin CLI or on wrfcoin.com for now.'
              : "Governance isn't active on this network yet, so there are "
                    'no proposals to show.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
