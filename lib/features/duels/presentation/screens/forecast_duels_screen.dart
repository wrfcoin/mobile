import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../data/models/duel_model.dart';
import '../../data/repositories/duel_repository.dart';
import '../providers/duels_provider.dart';
import '../widgets/duel_card.dart';

const double _maxContentWidth = 760;

/// The public duel board, with a form to open one (same routes as the web
/// page /duels). There are no stakes anywhere: free play, judged by the chain.
class ForecastDuelsScreen extends ConsumerWidget {
  const ForecastDuelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(duelBoardProvider);
    final wallet = ref.watch(duelWalletProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forecast duels'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(duelBoardProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: board.when(
            loading: () => const _Loading(),
            error: (_, _) => AppErrorWidget(
              title: 'Duels are unavailable right now',
              message: 'Nothing about the duels is confirmed; try again.',
              onRetry: () => ref.invalidate(duelBoardProvider),
            ),
            data: (result) => result.fold(
              (failure) => failure is NotAvailableFailure
                  ? const _NotSwitchedOn()
                  : AppErrorWidget.fromFailure(
                      failure,
                      onRetry: () => ref.invalidate(duelBoardProvider),
                    ),
              (data) => _Board(board: data, wallet: wallet),
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Loading duels…'),
      ],
    ),
  );
}

class _NotSwitchedOn extends StatelessWidget {
  const _NotSwitchedOn();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_outlined, size: 48, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text(
            'Forecast duels are not switched on yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6),
          Text(
            'This server does not run duels yet.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _Board extends ConsumerWidget {
  const _Board({required this.board, required this.wallet});

  final DuelBoard board;
  final String? wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(duelBoardProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Two forecasters, one station, one hour. After the reveal, the '
            "chain's own scoring decides who forecast better.",
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            duelFreePlayNote,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _OpenDuelCard(wallet: wallet),
          const SizedBox(height: 20),
          _Section(
            title: 'Open: take the other side',
            duels: board.open,
            you: wallet,
            empty: 'No open duels right now. Open one above.',
          ),
          _Section(
            title: 'In progress',
            duels: board.live,
            you: wallet,
            empty: 'No duel is running.',
          ),
          _Section(
            title: 'Finished',
            duels: board.finished,
            you: wallet,
            empty: 'No duel has finished yet.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.duels,
    required this.you,
    required this.empty,
  });

  final String title;
  final List<Duel> duels;
  final String? you;
  final String empty;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title (${duels.length})',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (duels.isEmpty)
          Text(empty, style: const TextStyle(color: AppColors.textSecondary))
        else
          for (final duel in duels)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DuelCard(
                duel: duel,
                you: you,
                onTap: () => context.push('/collect/duels/${duel.id}'),
              ),
            ),
      ],
    ),
  );
}

class _OpenDuelCard extends ConsumerStatefulWidget {
  const _OpenDuelCard({required this.wallet});

  final String? wallet;

  @override
  ConsumerState<_OpenDuelCard> createState() => _OpenDuelCardState();
}

class _OpenDuelCardState extends ConsumerState<_OpenDuelCard> {
  final _alias = TextEditingController();
  final _opponent = TextEditingController();
  late final List<DateTime> _hours = duelTargetHourOptions(DateTime.now());
  late DateTime _target = _hours.first;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _alias.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _alias.dispose();
    _opponent.dispose();
    super.dispose();
  }

  bool get _aliasValid =>
      stationAliasPattern.hasMatch(_alias.text.trim().toLowerCase());

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await ref
        .read(duelRepositoryProvider)
        .open(
          OpenDuelInput(
            stationAlias: _alias.text,
            targetAt: _target,
            opponent: _opponent.text,
          ),
        );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _busy = false;
        _message = failure.message;
      }),
      (duel) {
        setState(() => _busy = false);
        ref.invalidate(duelBoardProvider);
        context.push('/collect/duels/${duel.id}');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = widget.wallet;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open a duel',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (wallet == null) ...[
              const Text(
                'You need a wallet to open or accept a duel. Your wallet is '
                'your account.',
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => context.go('/wallet'),
                child: const Text('Open your wallet'),
              ),
            ] else ...[
              TextField(
                controller: _alias,
                maxLength: 15,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Station alias',
                  hintText: 'st_7d29a4c1e0b8',
                  counterText: '',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _alias.text = phoneStationAlias(wallet),
                  child: const Text("Use this phone's station"),
                ),
              ),
              DropdownButtonFormField<DateTime>(
                initialValue: _target,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Target hour (UTC)',
                ),
                items: [
                  for (final hour in _hours)
                    DropdownMenuItem(
                      value: hour,
                      child: Text(
                        hour
                            .toIso8601String()
                            .substring(0, 16)
                            .replaceFirst('T', ' '),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _target = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _opponent,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Opponent wallet (optional)',
                  hintText: '0x… or leave open',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy || !_aliasValid ? null : _submit,
                child: Text(_busy ? 'Opening…' : 'Open duel'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Both players commit a 6-hour forecast for that hour with the '
                'forecast kit and link it before the lock.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(
                  _message!,
                  style: const TextStyle(color: AppColors.wcagWarning),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
