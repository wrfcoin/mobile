import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../data/models/duel_model.dart';
import '../../data/repositories/duel_repository.dart';
import '../providers/duels_provider.dart';
import '../widgets/duel_card.dart';

/// One duel (same routes as the web page /duels/:id). A signed-in wallet can
/// accept an open duel and link its own forecast commit before the lock;
/// anyone can hand in a linked forecast's record after the reveal.
class ForecastDuelScreen extends ConsumerWidget {
  const ForecastDuelScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forecast duel')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: duelIdPattern.hasMatch(id) ? _Loaded(id: id) : const _NoDuel(),
        ),
      ),
    );
  }
}

class _NoDuel extends StatelessWidget {
  const _NoDuel();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No duel here',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Check the link, or forecast duels are not switched on for this '
            'server yet.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duel = ref.watch(duelProvider(id));
    final you = ref.watch(duelWalletProvider).asData?.value;
    return duel.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => AppErrorWidget(
        title: 'This duel is unavailable right now',
        message: 'Nothing about it is confirmed; try again.',
        onRetry: () => ref.invalidate(duelProvider(id)),
      ),
      data: (result) => result.fold(
        (failure) => failure is NotAvailableFailure
            ? const _NoDuel()
            : AppErrorWidget.fromFailure(
                failure,
                onRetry: () => ref.invalidate(duelProvider(id)),
              ),
        (value) => _Detail(duel: value, you: you),
      ),
    );
  }
}

class _Notice {
  const _Notice(this.message, {this.ok = false});

  final String message;
  final bool ok;
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.duel, required this.you});

  final Duel duel;
  final String? you;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  final _commitId = TextEditingController();
  final _commitJson = TextEditingController();
  final _dataJson = TextEditingController();
  _Notice? _notice;
  bool _busy = false;

  Duel get duel => widget.duel;

  @override
  void initState() {
    super.initState();
    for (final controller in [_commitId, _commitJson, _dataJson]) {
      controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _commitId.dispose();
    _commitJson.dispose();
    _dataJson.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<dynamic> Function(DuelRepository repository) action,
    String success, {
    VoidCallback? onSuccess,
  }) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final result = await action(ref.read(duelRepositoryProvider));
    if (!mounted) return;
    result.fold(
      (Failure failure) => setState(() {
        _busy = false;
        _notice = _Notice(failure.message);
      }),
      (_) {
        onSuccess?.call();
        setState(() {
          _busy = false;
          _notice = _Notice(success, ok: true);
        });
        ref.invalidate(duelProvider(duel.id));
        ref.invalidate(duelBoardProvider);
      },
    );
  }

  void _handIn() {
    final DuelRecordInput record;
    try {
      record = DuelRecordInput.parse(_commitJson.text, _dataJson.text);
    } on FormatException catch (error) {
      setState(() => _notice = _Notice(error.message));
      return;
    }
    _run(
      (repository) => repository.handInRecord(duel.id, record),
      'Record checked against the chain.',
      onSuccess: () {
        _commitJson.clear();
        _dataJson.clear();
      },
    );
  }

  Future<void> _copyLink() async {
    final origin = Uri.parse(ApiConstants.effectiveBaseUrl).origin;
    await Clipboard.setData(ClipboardData(text: '$origin/duels/${duel.id}'));
    if (!mounted) return;
    setState(() => _notice = const _Notice('Link copied.', ok: true));
  }

  @override
  Widget build(BuildContext context) {
    final you = widget.you;
    final commitId = _commitId.text.trim().toLowerCase();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          duelFreePlayNote,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _copyLink,
            icon: const Icon(Icons.link),
            label: const Text('Copy link to this duel'),
          ),
        ),
        DuelCard(duel: duel, you: you),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _notice!.message,
              style: TextStyle(
                color: _notice!.ok ? AppColors.success : AppColors.wcagWarning,
              ),
            ),
          ),
        if (duel.canAccept(you))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      (repository) => repository.accept(duel.id),
                      'You are in. Link your forecast before the lock.',
                    ),
              child: const Text('Accept this duel'),
            ),
          ),
        if (you == null && duel.phase == 'open')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () => context.go('/wallet'),
              child: const Text('Open your wallet to accept this duel'),
            ),
          ),
        if (duel.canLink(you))
          _Section(
            title: 'Link your forecast',
            children: [
              TextField(
                controller: _commitId,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Your forecast commit id',
                  hintText: '64 hex characters from commit.json',
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _busy || !commitIdPattern.hasMatch(commitId)
                    ? null
                    : () => _run(
                        (repository) =>
                            repository.linkForecast(duel.id, commitId),
                        'Forecast linked. Reveal it after the target hour, '
                        'then hand in its record below.',
                        onSuccess: _commitId.clear,
                      ),
                child: const Text('Link forecast'),
              ),
            ],
          ),
        if (duel.needsRecords)
          _Section(
            title: 'Hand in a revealed forecast',
            children: [
              const Text(
                "After revealing, paste the forecast's commit.json and "
                'data.json. The server checks they hash to the linked commit '
                'and target this hour.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _commitJson,
                minLines: 3,
                maxLines: 6,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'commit.json'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dataJson,
                minLines: 3,
                maxLines: 6,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'data.json'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed:
                    _busy ||
                        _commitJson.text.trim().isEmpty ||
                        _dataJson.text.trim().isEmpty
                    ? null
                    : _handIn,
                child: const Text('Hand in record'),
              ),
            ],
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    ),
  );
}
