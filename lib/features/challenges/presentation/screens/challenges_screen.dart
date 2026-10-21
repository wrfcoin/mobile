import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../data/models/challenge_model.dart';
import '../../data/repositories/challenge_repository.dart';
import '../providers/challenges_provider.dart';
import '../widgets/challenge_leaderboard_widget.dart';

/// Release route boundary. The interactive screen is not constructed unless
/// a canonical challenge capability and repository are explicitly supplied.
class FriendChallengesRoute extends ConsumerWidget {
  const FriendChallengesRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capability = ref.watch(challengeCapabilityProvider);
    if (capability.available) return const ChallengesScreen();

    return Scaffold(
      appBar: AppBar(title: const Text('Friend Challenges')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.block_outlined,
                size: 56,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 16),
              const Text(
                'Friend Challenges unavailable',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                capability.reason,
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChallengesScreen extends ConsumerStatefulWidget {
  const ChallengesScreen({super.key});

  @override
  ConsumerState<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends ConsumerState<ChallengesScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _inviteCodeController;
  ChallengeFormat _selectedFormat = ChallengeFormat.headToHead;
  int _selectedTarget = 25;
  Duration _selectedDuration = const Duration(days: 3);

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _inviteCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChallengesState>(challengesProvider, (previous, next) {
      final previousCount = previous?.challenges.length ?? 0;
      final nextCount = next.challenges.length;
      final previousError = previous?.error;
      final nextError = next.error;

      if (nextError != null && nextError != previousError) {
        AppSnackbars.error(context, nextError);
      }

      if (nextError == null && nextCount > previousCount) {
        AppSnackbars.success(
          context,
          'Challenge ready',
          detail: 'Share the referral code and start collecting live.',
        );
      }
    });

    final state = ref.watch(challengesProvider);
    final selectedChallenge = state.selectedChallenge;

    return Scaffold(
      appBar: AppBar(title: const Text('Friend Challenges')),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.challenges.isEmpty
          ? AppErrorWidget.fromFailure(
              state.error!,
              onRetry: () => ref.invalidate(challengesProvider),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _OverviewCard(state: state),
                const SizedBox(height: 16),
                _ChallengeComposerCard(
                  titleController: _titleController,
                  descriptionController: _descriptionController,
                  inviteCodeController: _inviteCodeController,
                  selectedFormat: _selectedFormat,
                  selectedTarget: _selectedTarget,
                  selectedDuration: _selectedDuration,
                  creating: state.creating,
                  joining: state.joining,
                  onFormatChanged: (value) {
                    setState(() {
                      _selectedFormat = value;
                    });
                  },
                  onTargetChanged: (value) {
                    setState(() {
                      _selectedTarget = value;
                    });
                  },
                  onDurationChanged: (value) {
                    setState(() {
                      _selectedDuration = value;
                    });
                  },
                  onCreatePressed: _createChallenge,
                  onJoinPressed: _joinByReferralCode,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Live Competitions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (state.challenges.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No challenges yet. Create one and invite a friend with a referral code.',
                      ),
                    ),
                  )
                else
                  ...state.challenges.map((challenge) {
                    final isSelected = selectedChallenge?.id == challenge.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ChallengeSummaryCard(
                        challenge: challenge,
                        selected: isSelected,
                        onTap: () => ref
                            .read(challengesProvider.notifier)
                            .selectChallenge(challenge.id),
                      ),
                    );
                  }),
                if (selectedChallenge != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ChallengeLeaderboardWidget(
                        challenge: selectedChallenge,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _createChallenge() async {
    await ref
        .read(challengesProvider.notifier)
        .createChallenge(
          CreateChallengeInput(
            title: _titleController.text,
            description: _descriptionController.text,
            format: _selectedFormat,
            targetScore: _selectedTarget,
            duration: _selectedDuration,
          ),
        );

    if (!mounted) return;
    if (ref.read(challengesProvider).error == null) {
      _titleController.clear();
      _descriptionController.clear();
    }
  }

  Future<void> _joinByReferralCode() async {
    await ref
        .read(challengesProvider.notifier)
        .joinByReferralCode(_inviteCodeController.text);

    if (!mounted) return;
    if (ref.read(challengesProvider).error == null) {
      _inviteCodeController.clear();
      AppSnackbars.success(
        context,
        'Challenge joined',
        detail: 'Your score will update as new readings come in.',
      );
    }
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.state});

  final ChallengesState state;

  @override
  Widget build(BuildContext context) {
    final joinedCount = state.joinedChallenges.length;
    final liveCount = state.joinedChallenges
        .where((challenge) => challenge.status == ChallengeStatus.live)
        .length;
    final inviteCodes = state.joinedChallenges
        .where((challenge) => challenge.status != ChallengeStatus.completed)
        .length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppColors.primaryDark, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Turn weather collection into a live race.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a head-to-head duel or a team relay, send the referral code, and watch the leaderboard move as readings land.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(label: 'Joined', value: '$joinedCount'),
              _MetricPill(label: 'Live now', value: '$liveCount'),
              _MetricPill(label: 'Codes active', value: '$inviteCodes'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ChallengeComposerCard extends StatelessWidget {
  const _ChallengeComposerCard({
    required this.titleController,
    required this.descriptionController,
    required this.inviteCodeController,
    required this.selectedFormat,
    required this.selectedTarget,
    required this.selectedDuration,
    required this.creating,
    required this.joining,
    required this.onFormatChanged,
    required this.onTargetChanged,
    required this.onDurationChanged,
    required this.onCreatePressed,
    required this.onJoinPressed,
  });

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController inviteCodeController;
  final ChallengeFormat selectedFormat;
  final int selectedTarget;
  final Duration selectedDuration;
  final bool creating;
  final bool joining;
  final ValueChanged<ChallengeFormat> onFormatChanged;
  final ValueChanged<int> onTargetChanged;
  final ValueChanged<Duration> onDurationChanged;
  final VoidCallback onCreatePressed;
  final VoidCallback onJoinPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create or join',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Challenge title',
                hintText: 'Bay weather sprint',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText:
                    'Race to 25 readings before the weekend front arrives.',
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ChallengeFormat>(
              segments: const <ButtonSegment<ChallengeFormat>>[
                ButtonSegment<ChallengeFormat>(
                  value: ChallengeFormat.headToHead,
                  icon: Icon(Icons.sports_kabaddi),
                  label: Text('Head-to-head'),
                ),
                ButtonSegment<ChallengeFormat>(
                  value: ChallengeFormat.team,
                  icon: Icon(Icons.groups_2),
                  label: Text('Team'),
                ),
              ],
              selected: <ChallengeFormat>{selectedFormat},
              onSelectionChanged: (selection) {
                onFormatChanged(selection.first);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: selectedTarget,
                    decoration: const InputDecoration(labelText: 'Target'),
                    items: const <int>[15, 25, 50, 90]
                        .map(
                          (target) => DropdownMenuItem<int>(
                            value: target,
                            child: Text('$target readings'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        onTargetChanged(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<Duration>(
                    initialValue: selectedDuration,
                    decoration: const InputDecoration(labelText: 'Length'),
                    items:
                        const <Duration>[
                              Duration(days: 1),
                              Duration(days: 3),
                              Duration(days: 7),
                            ]
                            .map(
                              (duration) => DropdownMenuItem<Duration>(
                                value: duration,
                                child: Text(_durationLabel(duration)),
                              ),
                            )
                            .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        onDurationChanged(value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: creating ? null : onCreatePressed,
                icon: creating
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline),
                label: Text(
                  creating ? 'Creating challenge...' : 'Create challenge',
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 18),
            TextField(
              controller: inviteCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Referral code',
                hintText: 'RADAR-21',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: joining ? null : onJoinPressed,
                icon: joining
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1),
                label: Text(joining ? 'Joining...' : 'Join by referral code'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _durationLabel(Duration duration) {
    if (duration.inDays == 1) return '24 hours';
    return '${duration.inDays} days';
  }
}

class _ChallengeSummaryCard extends StatelessWidget {
  const _ChallengeSummaryCard({
    required this.challenge,
    required this.selected,
    required this.onTap,
  });

  final ChallengeModel challenge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(challenge.status);
    final remaining = challenge.endsAt.difference(DateTime.now());
    final timeLabel = remaining.isNegative
        ? 'Ended'
        : remaining.inHours >= 24
        ? '${remaining.inDays}d left'
        : '${remaining.inHours}h left';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? accent : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      challenge.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _StatusBadge(label: challenge.status.label, color: accent),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                challenge.description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: challenge.format == ChallengeFormat.team
                        ? Icons.groups_2
                        : Icons.sports_kabaddi,
                    label: challenge.format.label,
                  ),
                  _InfoChip(
                    icon: Icons.flag_outlined,
                    label: '${challenge.targetScore} ${challenge.metricLabel}',
                  ),
                  _InfoChip(icon: Icons.schedule, label: timeLabel),
                  _InfoChip(icon: Icons.qr_code_2, label: challenge.inviteCode),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: challenge.progress,
                backgroundColor: AppColors.surfaceLight,
              ),
              const SizedBox(height: 8),
              Text(
                '${challenge.participantCount} competitors • top score ${challenge.topScore}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(ChallengeStatus status) {
    return switch (status) {
      ChallengeStatus.pending => AppColors.warning,
      ChallengeStatus.live => AppColors.success,
      ChallengeStatus.completed => AppColors.primary,
    };
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
