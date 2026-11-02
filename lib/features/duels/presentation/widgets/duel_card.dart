import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/duel_model.dart';

final DateFormat _when = DateFormat('MMM d, y h:mm a');

String _time(DateTime? value) =>
    value == null ? '—' : _when.format(value.toLocal());

Color _phaseColor(String phase) => switch (phase) {
  'open' || 'committing' => AppColors.primary,
  'waiting_for_target' || 'judging' => AppColors.wcagWarning,
  'resolved' => AppColors.success,
  _ => AppColors.textSecondary,
};

/// One duel: the station, the hour, both sides and the server's verdict.
class DuelCard extends StatelessWidget {
  const DuelCard({super.key, required this.duel, this.you, this.onTap});

  final Duel duel;
  final String? you;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final winner = duel.outcome?.winner;
    final challenger = _Side(
      entry: duel.creator,
      label: 'Challenger',
      you: you,
      winner: winner != null && winner == duel.creator?.address,
    );
    final opponent = _Side(
      entry: duel.opponent,
      label: 'Opponent',
      you: you,
      winner: winner != null && winner == duel.opponent?.address,
    );
    final color = _phaseColor(duel.phase);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Station ${duel.stationAlias}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  duelPhaseLabel(duel.phase),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Target hour ${_time(duel.targetAt)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              Text(
                'Lock ${_time(duel.lockAt)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        challenger,
                        const SizedBox(height: 8),
                        opponent,
                      ],
                    );
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: challenger),
                        const SizedBox(width: 8),
                        Expanded(child: opponent),
                      ],
                    ),
                  );
                },
              ),
              if (duel.outcome != null) ...[
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${duel.outcome!.label}. ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: duel.outcome!.note ?? ''),
                    ],
                  ),
                ),
              ],
              if (duel.invitedOpponent != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Invited: ${shortDuelAddress(duel.invitedOpponent!)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.entry,
    required this.label,
    required this.you,
    required this.winner,
  });

  final DuelEntry? entry;
  final String label;
  final String? you;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final current = entry;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: winner ? AppColors.success : AppColors.border,
          width: winner ? 2 : 1,
        ),
      ),
      child: current == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(),
                const SizedBox(height: 4),
                const Text('Open seat'),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(),
                const SizedBox(height: 4),
                Text(
                  '${shortDuelAddress(current.address)}'
                  '${current.address == you ? ' (You)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                _Fact(
                  'Forecast',
                  current.commitId == null
                      ? 'Not linked yet'
                      : current.recordVerified
                      ? 'Linked and proven'
                      : 'Linked',
                ),
                _Fact('Temperature', _temperature(current)),
                _Fact('Chain reward', _reward(current)),
                if (current.invalidReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Entry not valid: '
                      '${current.invalidReason!.replaceAll('_', ' ')}',
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _label() => Text(
    winner ? '$label · Winner' : label,
    style: TextStyle(
      color: winner ? AppColors.success : AppColors.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  );

  static String _temperature(DuelEntry entry) {
    final value = entry.temperatureC;
    if (value != null) return '${value.toStringAsFixed(1)} °C';
    return entry.commitId != null ? 'Hidden until revealed' : '—';
  }

  static String _reward(DuelEntry entry) {
    if (entry.chainReward == null) return 'Not decided yet';
    final formatted = formatWrfBaseUnits(entry.chainReward);
    if (formatted == null) return 'Unavailable';
    return entry.chainRewardFinalized ? formatted : '$formatted (not final)';
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
