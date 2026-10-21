import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/wrf_units.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../wallet/presentation/providers/transactions_provider.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
import '../../../wallet/presentation/widgets/transaction_tile.dart';
import '../../data/explorer_models.dart';
import '../../data/explorer_remote_datasource.dart';
import '../providers/chain_explorer_provider.dart';

/// Shown for any value the backend did not report. Never a made-up number.
const String kUnknownValue = '—';

String formatTipAge(int? seconds) {
  if (seconds == null) return kUnknownValue;
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min ${seconds % 60} s';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

/// A block or transaction hash, shortened; never an address.
String shortHash(String? hash) {
  if (hash == null) return kUnknownValue;
  if (hash.length <= 14) return hash;
  return '${hash.substring(0, 8)}…${hash.substring(hash.length - 4)}';
}

class ChainScreen extends ConsumerStatefulWidget {
  const ChainScreen({super.key});

  @override
  ConsumerState<ChainScreen> createState() => _ChainScreenState();
}

class _ChainScreenState extends ConsumerState<ChainScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  late final ChainReadScope _scope;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The scope outlives a screen instance: make sure a visit starts with a live token.
    _scope = ref.read(chainReadScopeProvider);
    if (_scope.token.isCancelled) _scope.cancelAndRenew();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    if (_foreground) _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _scope.release(); // cancels this visit's reads, retries and detail reads; the scope stays usable
    super.dispose();
  }

  /// Another page (or a sheet) over this one: cancel what is in flight.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final covered = ModalRoute.of(context)?.isCurrent == false;
    if (covered && !_covered) _scope.cancelAndRenew();
    _covered = covered;
  }

  /// Every refresh path goes through this: mounted, foreground and visible.
  bool get _canRefresh =>
      mounted && _foreground && ModalRoute.of(context)?.isCurrent != false;

  /// Polling runs only while the app is in the foreground and this page is
  /// mounted: any other lifecycle state cancels the timer.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _foreground) return;
    _foreground = resumed;
    if (resumed) {
      _startPolling();
      _refresh();
    } else {
      _stopPolling();
      _scope.cancelAndRenew(); // in-flight reads and pending retries stop too
      _scope.cancelDetails();
    }
  }

  void _startPolling() {
    _stopPolling();
    final configured = ref.read(chainPollIntervalProvider);
    final interval = configured < chainPollFloor ? chainPollFloor : configured;
    _timer = Timer.periodic(interval, (_) {
      _refresh();
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refresh() async {
    if (!_canRefresh) return;
    // Re-check the session from storage (no request, no login).
    ref.invalidate(chainAccountVisibleProvider);
    await ref.read(chainSnapshotProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(chainSnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Chain')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _StatusHeader(summary: snapshot.value?.summary),
            const SizedBox(height: 16),
            _RecentBlocks(
              loading: !snapshot.hasValue,
              blocks: snapshot.value?.blocks,
            ),
            const SizedBox(height: 16),
            const _MyAccountCard(),
          ],
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.summary});

  /// null while the first read is in flight.
  final ExplorerSummary? summary;

  static (String, Color) _pill(ChainStatus status) => switch (status) {
    ChainStatus.producing => ('Producing', AppColors.success),
    ChainStatus.stalled => ('Stalled', AppColors.error),
    ChainStatus.degraded => ('Degraded', AppColors.wcagWarning),
    ChainStatus.unknown => ('Unknown', AppColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final (label, color) = _pill(s?.status ?? ChainStatus.unknown);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Semantics(
                  label: 'Chain status: $label',
                  child: Container(
                    key: const Key('chain-status-pill'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      border: Border.all(color: color),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      s == null ? 'Loading…' : label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Stat(
              label: 'Height',
              value: s?.height == null ? kUnknownValue : '${s!.height}',
              valueKey: const Key('chain-height'),
            ),
            _Stat(
              label: 'Blocks / min',
              value: s?.blocksPerMinute == null
                  ? kUnknownValue
                  : s!.blocksPerMinute!.toStringAsFixed(1),
              valueKey: const Key('chain-bpm'),
            ),
            _Stat(
              label: 'Tip age',
              value: formatTipAge(s?.tipAgeSeconds),
              valueKey: const Key('chain-tip-age'),
            ),
            _Stat(
              label: 'Peers',
              value: s?.peerCount == null ? kUnknownValue : '${s!.peerCount}',
              valueKey: const Key('chain-peers'),
            ),
            _Stat(
              label: 'Faucet',
              value: switch (s?.faucetFunded) {
                true => 'Funded',
                false => 'Empty',
                null => 'Unknown',
              },
              valueKey: const Key('chain-faucet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            value,
            key: valueKey,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _RecentBlocks extends ConsumerWidget {
  const _RecentBlocks({required this.loading, required this.blocks});

  final bool loading;
  final List<ChainBlock>? blocks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = blocks;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent blocks',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (loading)
              const Text('Loading…')
            else if (list == null)
              const Text(
                'Recent blocks are unavailable right now.',
                key: Key('chain-blocks-unavailable'),
              )
            else if (list.isEmpty)
              const Text('No blocks reported.')
            else
              for (final block in list)
                ListTile(
                  key: Key('chain-block-${block.height}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('#${block.height}'),
                  subtitle: Text(
                    '${shortHash(block.hash)} · '
                    '${block.transactionCount ?? kUnknownValue} tx',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showBlock(context, ref, block.height!),
                ),
          ],
        ),
      ),
    );
  }

  void _showBlock(BuildContext context, WidgetRef ref, int height) {
    final source = ref.read(explorerRemoteDataSourceProvider);
    final scope = ref.read(chainReadScopeProvider);
    final token = scope.newDetailToken();
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<ChainBlock?>(
            future: source.fetchBlock(height, cancelToken: token),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final b = snapshot.data;
              if (b == null) {
                return Text('Block #$height is unavailable right now.');
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Block #$height',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _Stat(label: 'Hash', value: shortHash(b.hash)),
                  _Stat(label: 'Previous', value: shortHash(b.previousHash)),
                  _Stat(
                    label: 'Time (UTC)',
                    value: b.timestamp == null
                        ? kUnknownValue
                        : b.timestamp!.toIso8601String(),
                  ),
                  _Stat(
                    label: 'Transactions',
                    value: b.transactionCount == null
                        ? kUnknownValue
                        : '${b.transactionCount}',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ).whenComplete(() => scope.closeDetail(token));
  }
}

/// Shown only with a signed-in wallet; reuses the wallet and activity
/// providers (no new endpoints) and never triggers a login.
class _MyAccountCard extends ConsumerWidget {
  const _MyAccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gate on the CURRENT session before touching any private provider: a cached
    // wallet outlives sign-out, session expiry and rejection.
    if (ref.watch(chainAccountVisibleProvider).value != true) {
      return const SizedBox.shrink();
    }
    final wallet = ref.watch(walletProvider).value;
    if (wallet == null) return const SizedBox.shrink();
    final activity = ref.watch(transactionsProvider).value;
    final recent = (activity == null || activity.historyUnavailable)
        ? const []
        : activity.items.take(3).toList();
    final balance = wrfBaseUnitsToDisplay(wallet.balance) ?? wallet.balance;
    return Card(
      key: const Key('chain-my-account'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My account', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _Stat(
              label: 'Address',
              value: KeyManager.maskAddress(wallet.address),
            ),
            _Stat(label: 'Balance', value: '$balance WRF'),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Recent activity',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              for (final tx in recent) TransactionTile(transaction: tx),
            ],
          ],
        ),
      ),
    );
  }
}
