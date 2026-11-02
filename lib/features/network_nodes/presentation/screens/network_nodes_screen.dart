import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/network/public_read.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/public_read_widgets.dart';
import '../../data/models/network_nodes_model.dart';
import '../providers/network_nodes_provider.dart';

const _unavailable = 'Unavailable';
const _downloads = 'https://wrfcoin.com/downloads';

String _short(String hex, {int head = 8, int tail = 6}) =>
    hex.length > head + tail + 1
    ? '${hex.substring(0, head)}…${hex.substring(hex.length - tail)}'
    : hex;

/// Base units as exact WRF, or "Unavailable" when the node gave no value.
String _wrf(String? units) => publicWrf(units) ?? _unavailable;

/// Who signs the blocks, who has bonded a node and who checks readings, on the
/// participation ladder (node, bonded node, attester, producer). Same route as
/// the website's /nodes page, read from the chain by the backend: a section the
/// node could not answer reads "unavailable", never zero.
class NetworkNodesScreen extends ConsumerWidget {
  const NetworkNodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(networkNodesProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    void reload() => ref.invalidate(networkNodesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Producers and bonded nodes')),
      body: RefreshIndicator(
        onRefresh: () async {
          reload();
          await ref.read(networkNodesProvider.future);
        },
        child: ResponsiveListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              'Who signs the blocks, who has bonded a node, and who checks weather readings on the WRFCoin testnet, read from the chain itself. Anyone can climb: run a node, bond it, then earn a seat as an attester and a producer.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ...async.when(
              loading: () => [
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(
                  'Reading the chain…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ],
              // The repository does not throw; this is a last resort.
              error: (_, _) => [_unavailableCard(reload)],
              data: (read) => switch (read) {
                PublicLoaded(:final data) => [_Loaded(nodes: data)],
                PublicNotFound() => const [
                  PublicNoticeCard(
                    icon: Icons.info_outline,
                    title: 'Not switched on yet',
                    message: 'This server does not publish the producer and bonded-node list yet.',
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
    title: 'The producer and bonded-node list is unavailable right now',
    message: 'The chain node could not answer.',
    onRetry: reload,
  );
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.nodes});

  final NetworkNodes nodes;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final chain = nodes.chain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Ladder(nodes: nodes),
        const SizedBox(height: 12),
        PublicSectionCard(
          title: 'Producers',
          count: 'Rung 4 · newest blocks',
          children: [_ProducersBody(producers: nodes.producers)],
        ),
        const SizedBox(height: 12),
        PublicSectionCard(
          title: 'Bonded nodes',
          count: 'Rung 2',
          children: [_BondedBody(bonded: nodes.bonded)],
        ),
        const SizedBox(height: 12),
        PublicSectionCard(
          title: 'Attesters',
          count: 'Rung 3',
          children: [_AttestersBody(attesters: nodes.attesters)],
        ),
        const SizedBox(height: 12),
        Text(
          '${chain.networkId == null ? '' : '${chain.networkId}${chain.chainId == null ? '' : ' · chain ${chain.chainId}'} · '}Checked ${publicWhen(nodes.checkedAt)}. Paid totals are everything the chain has credited to each payout account.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        const PublicLinkRow(label: 'Run a node', url: _downloads),
      ],
    );
  }
}

class _Ladder extends StatelessWidget {
  const _Ladder({required this.nodes});

  final NetworkNodes nodes;

  @override
  Widget build(BuildContext context) {
    final producers = nodes.producers;
    final rungs = <(String, String, String)>[
      (
        'Node',
        'Holds and checks the whole chain.',
        nodes.chain.ok
            ? 'Height ${publicCount(nodes.chain.height)}'
            : _unavailable,
      ),
      (
        'Bonded node',
        'Locks a bond and is paid each settlement epoch.',
        nodes.bonded.ok ? '${nodes.bonded.nodes.length} bonded' : _unavailable,
      ),
      (
        'Attester',
        'Confirms weather readings before they are paid.',
        nodes.attesters.ok
            ? '${nodes.attesters.ids.length} seated'
            : _unavailable,
      ),
      (
        'Producer',
        'Signs the blocks.',
        producers.ok
            ? '${producers.producing} of ${producers.members.length} producing'
            : _unavailable,
      ),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          children: [
            for (final (i, (title, body, value)) in rungs.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            body,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionUnavailable extends StatelessWidget {
  const _SectionUnavailable(this.what);

  final String what;

  @override
  Widget build(BuildContext context) => Text(
    '$what unavailable: the chain node did not answer this part.',
    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _ProducersBody extends StatelessWidget {
  const _ProducersBody({required this.producers});

  final Producers producers;

  @override
  Widget build(BuildContext context) {
    if (!producers.ok) return const _SectionUnavailable('Producer activity');
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final w = producers.window;
    final extras = [
      if ((w?.unreadable ?? 0) > 0) ', ${w!.unreadable} could not be read',
      if ((w?.unsigned ?? 0) > 0) ', ${w!.unsigned} unsigned',
    ].join();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in producers.members)
          _ProducerRow(producer: p, read: w?.read),
        for (final p in producers.unrostered)
          _ProducerRow(producer: p, read: w?.read),
        const SizedBox(height: 8),
        Text(
          'Blocks ${publicCount(w?.fromHeight)}–${publicCount(w?.toHeight)}: ${publicCount(w?.read)} read$extras. Names come from the testnet genesis roster; activity comes from each block\'s producer key.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _ProducerRow extends StatelessWidget {
  const _ProducerRow({required this.producer, required this.read});

  final Producer producer;
  final int? read;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final small = TextStyle(color: muted, fontSize: 12);
    final last = producer.lastBlock;
    final blocks = producer.blocksInWindow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  producer.producerId ?? 'Unnamed producer',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                blocks == null
                    ? _unavailable
                    : '$blocks of ${publicCount(read)} blocks',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          Text('key ${_short(producer.publicKey)}', style: small),
          Text(
            last == null
                ? 'No block in this window'
                : 'Last block ${publicCount(last.height)} · ${publicWhen(last.time)}',
            style: small,
          ),
          Text('Paid in total: ${_wrf(producer.earnedTotal)}', style: small),
        ],
      ),
    );
  }
}

class _BondedBody extends StatelessWidget {
  const _BondedBody({required this.bonded});

  final BondedNodes bonded;

  @override
  Widget build(BuildContext context) {
    if (!bonded.ok) return const _SectionUnavailable('Bonded nodes');
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (bonded.nodes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No bonded nodes found',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'No registered bond appeared in the recent settlement epochs or the known list.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final node in bonded.nodes) _BondedRow(node: node),
        const SizedBox(height: 8),
        Text(
          'Current settlement epoch ${publicCount(bonded.epoch)}. Each bond is checked on chain; only registered bonds are listed.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _BondedRow extends StatelessWidget {
  const _BondedRow({required this.node});

  final BondedNode node;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final small = TextStyle(color: muted, fontSize: 12);
    final payout = node.lastPayout;
    final address = node.payoutAddress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  node.alias ?? 'Unnamed node',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (node.jailed) ...[
                const SizedBox(width: 8),
                const Text(
                  'Jailed',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          Text('bond ${_short(node.deploymentId)}', style: small),
          if (address != null)
            Text('pays ${_short(address, head: 6, tail: 4)}', style: small),
          Text('Bond: ${_wrf(node.principal)}', style: small),
          Text(
            payout == null
                ? 'Latest payout: none in the last epochs'
                : 'Latest payout: ${payout.pending ? 'Pending' : 'Paid'} ${_wrf(payout.amount)} · epoch ${publicCount(payout.epoch)}',
            style: small,
          ),
          Text(
            'Paid in total: ${_wrf(node.earnedTotal)}',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AttestersBody extends StatelessWidget {
  const _AttestersBody({required this.attesters});

  final Attesters attesters;

  @override
  Widget build(BuildContext context) {
    if (!attesters.ok) return const _SectionUnavailable('Attesters');
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final quorum = attesters.quorum;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${attesters.ids.length} seated${quorum == null ? '' : ' · $quorum must agree before a reading is paid'}',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 6),
        for (final id in attesters.ids)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(_short(id), style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
