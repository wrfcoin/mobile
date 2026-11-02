import '../../../weather/domain/models/coarse_location.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../wallet/presentation/widgets/wallet_reward_totals.dart';
import '../../../../core/formatting/app_formatters.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../wallet/data/models/wallet_model.dart';
import '../../../challenges/data/models/challenge_model.dart';
import '../../../challenges/data/repositories/challenge_repository.dart';
import '../../../challenges/presentation/providers/challenges_provider.dart';
import '../../../challenges/presentation/widgets/challenge_leaderboard_widget.dart';
import '../../../settings/presentation/widgets/settings_gear_button.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
import '../providers/collector_provider.dart';
import '../providers/mobile_station_status_provider.dart';
import '../widgets/owner_ledger_banner.dart';
import '../widgets/station_ownership_card.dart';
import '../../data/services/mobile_station_status_service.dart';
import '../../../../services/background/sync_worker.dart';
import '../widgets/sync_status.dart';
import '../../../social/proof_card_link.dart';

class CollectorDashboard extends ConsumerWidget {
  const CollectorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectorProvider);
    final walletAsync = ref.watch(walletProvider);
    final owner = walletAsync.asData?.value?.address;
    final stationStatus = owner == null
        ? null
        : ref.watch(mobileStationStatusProvider(owner));
    final stationMessage = stationStatus?.when(
      data: (status) => status.message,
      loading: () => 'Checking weather station registration…',
      error: (_, _) =>
          const MobileStationStatus(MobileStationPhase.unknown).message,
    );
    final appPreferences = ref.watch(appPreferencesProvider).preferences;
    final canCollect = appPreferences.consent.canCollect;
    final localizations = AppLocalizations.of(context);
    final challengeCapability = ref.watch(challengeCapabilityProvider);
    final challengesState = challengeCapability.available
        ? ref.watch(challengesProvider)
        : null;
    final featuredChallenge = challengesState?.selectedChallenge;
    final batteryImpact = ref.watch(batteryImpactEstimateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collect'),
        actions: [
          if (challengeCapability.available)
            Semantics(
              button: true,
              label: 'Open friend challenges',
              child: IconButton(
                tooltip: 'Challenges',
                icon: const Icon(Icons.groups_2_outlined),
                onPressed: () => context.push('/collect/challenges'),
              ),
            ),
          Semantics(
            button: true,
            label: 'Open field diagnostics mode',
            child: IconButton(
              tooltip: 'Field mode',
              icon: const Icon(Icons.radar),
              onPressed: () => context.push('/collect/field-mode'),
            ),
          ),
          const SettingsGearButton(),
        ],
      ),
      body: ResponsiveListView(
        maxContentWidth: 1040,
        children: [
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                color: AppColors.warning.withValues(alpha: 0.15),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sensor collection requires the mobile app. '
                          'Install on Android/iOS for full functionality.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!canCollect)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.privacy_tip, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(localizations.grantConsentHint)),
                      TextButton(
                        onPressed: () => context.push('/profile/privacy'),
                        child: const Text('Review'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (stationMessage != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Expanded(child: Text(stationMessage)),
                    IconButton(
                      tooltip: 'Refresh station status',
                      icon: const Icon(Icons.refresh),
                      onPressed: () =>
                          ref.invalidate(mobileStationStatusProvider(owner!)),
                    ),
                  ],
                ),
              ),
            ),
          if (stationStatus?.asData?.value.phase ==
                  MobileStationPhase.onChain &&
              !(stationStatus?.asData?.value.cached ?? true))
            const OwnerLedgerBanner(),
          if (stationStatus?.asData?.value.phase ==
                  MobileStationPhase.onChain &&
              !(stationStatus?.asData?.value.cached ?? true))
            StationOwnershipCard(onNavigate: (route) => context.push(route)),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(SyncWorker.earningWindowMessage),
            ),
          ),
          if (state.staleReadingsCount > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        SyncWorker.staleReadingsNotice(
                          state.staleReadingsCount,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss stale readings notice',
                      icon: const Icon(Icons.close),
                      onPressed: () => ref
                          .read(collectorProvider.notifier)
                          .acknowledgeStaleReadings(),
                    ),
                  ],
                ),
              ),
            ),
          // Collection toggle card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sensors,
                        size: 32,
                        color: state.isCollecting
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.isCollecting
                                  ? 'Collecting Data'
                                  : 'Collection Paused',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              state.isCollecting
                                  ? 'Every ${state.intervalMinutes} minutes'
                                  : 'Tap to start collecting',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: state.isCollecting,
                        onChanged: kIsWeb || !canCollect
                            ? null
                            : (v) {
                                if (v) {
                                  ref
                                      .read(collectorProvider.notifier)
                                      .startCollecting();
                                } else {
                                  ref
                                      .read(collectorProvider.notifier)
                                      .stopCollecting();
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.battery_saver_outlined,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Battery Impact',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        batteryImpact.label,
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    batteryImpact.detail,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'GPS gates collection at 50 m movement; barometer reads wait for movement or the next adaptive interval.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Current readings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Current Readings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SyncStatus(pendingCount: state.pendingSyncCount),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.currentReading != null) ...[
                    _ReadingRow(
                      icon: Icons.compress,
                      label: 'Pressure',
                      value: AppFormatters.formatPressure(
                        context,
                        appPreferences,
                        state.currentReading!.pressureHpa,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ReadingRow(
                      icon: Icons.location_on,
                      label: 'Location',
                      value:
                          '${CoarseLocation.coarsen(state.currentReading!.latitude).toStringAsFixed(1)}, '
                          '${CoarseLocation.coarsen(state.currentReading!.longitude).toStringAsFixed(1)}',
                    ),
                    const SizedBox(height: 8),
                    _ReadingRow(
                      icon: Icons.access_time,
                      label: 'Last Reading',
                      value: AppFormatters.formatDateTime(
                        context,
                        appPreferences,
                        state.currentReading!.timestamp,
                        includeDate: false,
                      ),
                    ),
                  ] else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No readings yet. Start collecting to see data.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  if (state.syncMessage != null ||
                      state.lastSyncAt != null) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    if (state.isSyncing)
                      const Row(
                        children: [
                          SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Syncing pending readings...',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        state.syncMessage ??
                            'Last synced ${AppFormatters.formatDateTime(context, appPreferences, state.lastSyncAt!)}',
                        style: TextStyle(
                          color: state.syncMessage == null
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Collect now button
          // Lane 1: also disable while a background sync is in progress to
          // avoid a duplicate submission race.
          if (state.isCollecting)
            OutlinedButton.icon(
              onPressed: state.isCollectingNow || state.isSyncing || !canCollect
                  ? null
                  : () => ref.read(collectorProvider.notifier).collectNow(),
              icon: state.isCollectingNow
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(
                state.isCollectingNow ? 'Collecting...' : 'Collect Now',
              ),
            ),

          const SizedBox(height: 16),

          // Sync Progress card — show both backend sync totals and the live
          // wallet reward categories that currently feed the earn loop UI.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sync Progress & Rewards',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        color: AppColors.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${state.syncedSubmissionCount}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              state.syncedSubmissionCount == 1
                                  ? 'reading synced to backend'
                                  : 'readings synced to backend',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pending sync: ${state.pendingSyncCount}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  const Text(
                    'Rewards Breakdown',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  walletAsync.when(
                    loading: () => const Text(
                      'Loading wallet rewards...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    error: (_, _) => const Text(
                      'Reward breakdown unavailable right now.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    data: (wallet) {
                      if (wallet == null) {
                        return const Text(
                          'Create or import a wallet to see reward totals.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        );
                      }

                      return Column(
                        children: [
                          WalletRewardTotals(
                            earnedBalanceTotal: wallet.earnedBalanceTotal,
                            weatherRewards: wallet.weatherRewards,
                            weatherRewardsPending: wallet.weatherRewardsPending,
                            weatherRewardsUnavailable:
                                wallet.weatherRewardsUnavailable,
                          ),
                          const SizedBox(height: 8),
                          _ReadingRow(
                            icon: Icons.account_balance_wallet,
                            label: 'Live balance',
                            value: wallet.balanceText,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.rewardTotalsAvailable
                        ? '${state.earnedRewardWrf.toStringAsFixed(2)} WRF settled'
                        : walletAsync.asData?.value?.earnedBalanceTotal != null
                        ? 'Total earned includes all reward sources.'
                        : 'Reward totals unavailable until the backend returns them.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (state.lastSubmissionId != null ||
                      state.lastSubmissionStatus != null ||
                      state.lastSyncAttemptAt != null) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    if (state.lastSubmissionId != null)
                      _ReadingRow(
                        icon: Icons.receipt_long_outlined,
                        label: 'Last Submission',
                        value: state.lastSubmissionId!,
                      ),
                    if (state.lastSubmissionId != null)
                      const SizedBox(height: 8),
                    if (state.lastSubmissionStatus != null)
                      _ReadingRow(
                        icon: Icons.verified_outlined,
                        label: 'Backend Status',
                        value: state.lastSubmissionStatus!,
                      ),
                    if (state.lastSubmissionStatus != null &&
                        state.lastSyncAttemptAt != null)
                      const SizedBox(height: 8),
                    if (state.lastSyncAttemptAt != null)
                      _ReadingRow(
                        icon: Icons.schedule,
                        label: 'Last Attempt',
                        value: _formatDateTime(state.lastSyncAttemptAt!),
                      ),
                  ],
                  if (proofCardPageUri(state.lastCommitId) != null) ...[
                    const SizedBox(height: 12),
                    // backend#229: the newest accepted reading opens as a
                    // public proof card showing the block it landed in.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('collector-share-proof-card'),
                        onPressed: () => ref
                            .read(proofCardLinkServiceProvider)
                            .share(state.lastCommitId!),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share proof card'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => context.push('/collect/validation'),
                      icon: const Icon(Icons.list_alt),
                      label: const Text('Open validation log'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (challengeCapability.available && challengesState != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Friend Challenges',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/collect/challenges'),
                          child: const Text('Open'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (challengesState.loading)
                      const LinearProgressIndicator()
                    else if (featuredChallenge == null)
                      const Text(
                        'Create a challenge, share the referral code, and race friends on live collection totals.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      )
                    else ...[
                      Text(
                        featuredChallenge.format == ChallengeFormat.team
                            ? 'Team battle'
                            : 'Head-to-head',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ChallengeLeaderboardWidget(
                        challenge: featuredChallenge,
                        compact: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sports_score),
              title: const Text('Forecast duels'),
              subtitle: const Text(
                'Two forecasters pick the same station and hour. The chain judges. '
                'Free play.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/collect/duels'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime dt) {
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}

class _ReadingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReadingRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
