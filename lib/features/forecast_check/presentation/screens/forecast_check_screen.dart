import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/network/public_read.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/public_read_widgets.dart';
import '../../data/models/forecast_check_model.dart';
import '../../data/repositories/forecast_check_repository.dart';
import '../providers/forecast_check_provider.dart';

const _unavailableLabel = 'Unavailable';
const _forecastingGuide =
    'https://github.com/wrfcoin/docs/blob/main/testnet/forecasting.md';

const _variables = <String, (String, String)>{
  'temperature_c': ('Temperature', '°C'),
  'pressure_hpa': ('Pressure', 'hPa'),
  'humidity_pct': ('Humidity', '%'),
};

String _label(String variable) => _variables[variable]?.$1 ?? variable;

/// A server number at the website's precision: two decimals, one for humidity.
String _fmt(double? value, String variable, {bool signed = false}) {
  if (value == null) return publicUnknown;
  final digits = variable == 'humidity_pct' ? 1 : 2;
  final unit = _variables[variable]?.$2 ?? '';
  final sign = signed && value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(digits)} $unit'.trimRight();
}

const _statusLabels = <String, String>{
  'scored': 'Scored',
  'pending': 'Waiting for readings',
  'unavailable': _unavailableLabel,
};

const _unavailableReasons = <String, String>{
  'no_chain_reading_in_target_hour':
      'No station reading landed on chain for the target hour.',
  'no_shared_variable':
      'The station did not report any variable this forecast predicted.',
};

/// Forecast check: how close forecasts committed on chain came to what the
/// station measured, next to NOAA's forecast for the same station and hour.
/// Same route and same rule as the website: every number is the server's, and
/// a figure it does not have reads "Unavailable", never an estimate.
class ForecastCheckScreen extends ConsumerWidget {
  const ForecastCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(forecastCheckProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    void reload() => ref.invalidate(forecastCheckProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Forecast check')),
      body: RefreshIndicator(
        onRefresh: () async {
          reload();
          await ref.read(forecastCheckProvider.future);
        },
        child: ResponsiveListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              "How close did forecasts committed on chain come to what the station measured? Each one is scored against the station's own readings on chain for the target hour, next to NOAA's forecast for the same station and hour.",
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ...async.when(
              loading: () => [
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(
                  'Loading scores…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ],
              // The repository does not throw; this is a last resort.
              error: (_, _) => [_unavailableCard(reload)],
              data: (read) => switch (read) {
                PublicLoaded(:final data) => [
                  _Loaded(summary: data),
                  const SizedBox(height: 12),
                  _HandInCard(onAdded: reload),
                ],
                PublicNotFound() => const [
                  PublicNoticeCard(
                    icon: Icons.info_outline,
                    title: 'Forecast check is not switched on yet',
                    message: 'This server does not score forecasts yet. Nothing on this page is estimated in the meantime.',
                  ),
                ],
                PublicRateLimited() => [
                  PublicNoticeCard(
                    icon: Icons.hourglass_empty,
                    title: 'Too many requests right now. Please wait a moment and try again.',
                    onRetry: reload,
                  ),
                ],
                PublicUnavailable() => [_unavailableCard(reload)],
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _unavailableCard(VoidCallback reload) => PublicNoticeCard(
    icon: Icons.cloud_off,
    title: 'Forecast check is unavailable right now.',
    onRetry: reload,
  );
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.summary});

  final ForecastCheckSummary summary;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final window = summary.windowDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PublicStatGrid(
          stats: [
            (
              window == null ? 'Scored' : 'Scored ($window days)',
              publicCount(summary.scored),
              AppColors.success,
            ),
            (
              'Waiting for readings',
              publicCount(summary.pending),
              AppColors.primary,
            ),
            (
              'No reading to score',
              publicCount(summary.unavailable),
              AppColors.warning,
            ),
            (
              'Stations',
              publicCount(summary.stationCount),
              AppColors.secondary,
            ),
          ],
        ),
        if (!summary.available) ...[
          const SizedBox(height: 12),
          Text(
            summary.reason ?? 'Nothing has been scored yet.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 12),
        PublicSectionCard(
          title: 'How far off, on average',
          count: window == null ? null : 'last $window days',
          children: [
            for (final variable in summary.variables)
              _VariableRow(skill: variable),
            const SizedBox(height: 8),
            Text(
              '"Average miss" is the mean absolute error. NOAA figures compare only the forecasts that have a NOAA forecast for the same station and hour.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PublicSectionCard(
          title: 'Recent forecasts',
          count: '${publicCount(summary.recent.length)} shown',
          children: summary.recent.isEmpty
              ? [
                  Text(
                    'No forecast has been handed in yet.',
                    style: TextStyle(color: muted),
                  ),
                ]
              : [
                  for (final record in summary.recent)
                    _RecordRow(record: record),
                ],
        ),
      ],
    );
  }
}

class _VariableRow extends StatelessWidget {
  const _VariableRow({required this.skill});

  final VariableSkill skill;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final v = skill.variable;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_label(v), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            skill.hasChain
                ? '${publicCount(skill.n)} scored · average miss ${_fmt(skill.mae, v)} · bias ${_fmt(skill.bias, v, signed: true)}'
                : '0 scored · average miss $_unavailableLabel',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            skill.hasNoaa
                ? 'Same forecasts: on chain ${_fmt(skill.chainMaeVsNoaa, v)}, NOAA ${_fmt(skill.noaaMae, v)}, over ${publicCount(skill.noaaN)} forecast${skill.noaaN == 1 ? '' : 's'}'
                : 'Against NOAA: $_unavailableLabel${skill.vsNoaaReason == null ? '' : '. ${skill.vsNoaaReason}'}',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final ForecastRecord record;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final v = record.mainVariable;
    final score = record.scores[v];
    final scored = record.status == 'scored';
    final reason = record.unavailableReason;
    final statusColor = switch (record.status) {
      'scored' => AppColors.success,
      'pending' => AppColors.primary,
      _ => AppColors.warning,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.stationAlias ?? publicUnknown,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _statusLabels[record.status] ?? record.status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Text(
            '${record.modelId ?? 'model not stated'} · target ${publicWhen(record.validAt)}',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          if (record.status == 'unavailable' && reason != null)
            Text(
              _unavailableReasons[reason] ?? reason,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          const SizedBox(height: 4),
          Text(
            scored && score != null
                ? '${_label(v)}: forecast ${_fmt(score.forecast, v)}, measured ${_fmt(score.truth, v)}, off by ${_fmt(score.error, v, signed: true)}'
                : '${_label(v)}: forecast ${_fmt(record.forecast[v], v)}',
            style: const TextStyle(fontSize: 13),
          ),
          if (scored)
            Text(
              score != null && score.hasNoaa
                  ? 'NOAA: ${_fmt(score.noaaValue, v)}, off by ${_fmt(score.noaaError, v, signed: true)}, ${_hours(score.noaaLeadHours)} ahead'
                  : 'NOAA: $_unavailableLabel${record.noaaReason == null ? '' : '. ${record.noaaReason}'}',
              style: TextStyle(color: muted, fontSize: 12),
            ),
        ],
      ),
    );
  }

  static String _hours(double? hours) {
    if (hours == null) return publicUnknown;
    final whole = hours == hours.roundToDouble();
    return '${whole ? hours.toInt() : hours} h';
  }
}

/// Hands in a forecast kit record. The server checks it hashes to the chain
/// commit, so the form needs no login and asks for nothing personal.
class _HandInCard extends ConsumerStatefulWidget {
  const _HandInCard({required this.onAdded});

  final VoidCallback onAdded;

  @override
  ConsumerState<_HandInCard> createState() => _HandInCardState();
}

class _HandInCardState extends ConsumerState<_HandInCard> {
  final _commit = TextEditingController();
  final _data = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _accepted = false;

  @override
  void dispose() {
    _commit.dispose();
    _data.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final (record, problem) = ForecastHandIn.fromFiles(
      _commit.text,
      _data.text,
    );
    if (record == null) {
      setState(() {
        _message = problem;
        _accepted = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await ref
        .read(forecastCheckRepositoryProvider)
        .handIn(record);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.message;
      _accepted = result.accepted;
    });
    if (result.accepted) widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return PublicSectionCard(
      title: 'Hand in your forecast',
      children: [
        Text(
          "Committed a forecast with the forecast kit? After you reveal it, paste its commit.json and data.json here. The server checks they hash to your commit on chain, then scores it once the station's readings land.",
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commit,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'commit.json'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _data,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'data.json'),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Checking…' : 'Hand in forecast'),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(
            _message!,
            style: TextStyle(
              fontSize: 13,
              color: _accepted ? AppColors.success : AppColors.wcagWarning,
            ),
          ),
        ],
        const SizedBox(height: 8),
        const PublicLinkRow(
          label: 'How to forecast with the kit',
          url: _forecastingGuide,
        ),
      ],
    );
  }
}
