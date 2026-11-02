import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../settings/presentation/widgets/settings_gear_button.dart';
import '../providers/proposals_provider.dart';
import '../widgets/proposal_card.dart';

class ProposalListScreen extends ConsumerWidget {
  const ProposalListScreen({super.key, this.leading});

  /// The app bar's back button, when opened by a link with nothing to pop to.
  final Widget? leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposalsAsync = ref.watch(proposalsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: leading,
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
          onRefresh: () async => ref.invalidate(proposalsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                      'No proposals yet. Submitting proposals isn\'t available '
                      'on testnet yet.',
                      textAlign: TextAlign.center,
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
