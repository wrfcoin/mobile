import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/communities_provider.dart';
import '../widgets/cluster_card.dart';
import '../../data/models/cluster_model.dart';

/// Dark-launched communities screen.
///
/// NOT wired into app navigation yet — that happens in a future round once
/// the backend endpoints exist.  The screen is fully functional against the
/// fake service.
class CommunitiesScreen extends ConsumerWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(communitiesProvider);

    if (state.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Communities'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(communitiesProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.error != null) _ErrorBanner(message: state.error!.message),
          _LocationToggle(
            enabled: state.locationSharingEnabled,
            onChanged: (v) => ref
                .read(communitiesProvider.notifier)
                .setLocationSharing(enabled: v),
          ),
          const Divider(height: 1),
          if (state.joinedClusters.isNotEmpty) ...[
            _SectionHeader(
              title: 'My Clusters',
              trailing: _JoinButton(joining: state.joining),
            ),
            ...state.joinedClusters.map(
              (c) => ClusterCard(
                key: ValueKey(c.id),
                cluster: c,
                selected: state.selectedCluster?.id == c.id,
                onTap: () =>
                    ref.read(communitiesProvider.notifier).selectCluster(c.id),
              ),
            ),
            const Divider(height: 1),
          ],
          _SectionHeader(
            title: 'Nearby Clusters',
            trailing: state.joinedClusters.isEmpty
                ? _JoinButton(joining: state.joining)
                : null,
          ),
          Expanded(
            child: state.clusters.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    itemCount: state.clusters.length,
                    itemBuilder: (context, index) {
                      final cluster = state.clusters[index];
                      return ClusterCard(
                        key: ValueKey(cluster.id),
                        cluster: cluster,
                        selected: state.selectedCluster?.id == cluster.id,
                        onTap: () => ref
                            .read(communitiesProvider.notifier)
                            .selectCluster(cluster.id),
                      );
                    },
                  ),
          ),
          if (state.selectedCluster != null) ...[
            const Divider(height: 1),
            _ClusterDetail(cluster: state.selectedCluster!),
          ],
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _LocationToggle extends StatelessWidget {
  const _LocationToggle({required this.enabled, required this.onChanged});
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      title: const Text('Nearby discovery'),
      subtitle: const Text(
        'Share coarse location (~1 km tile) to find clusters',
      ),
      value: enabled,
      onChanged: onChanged,
      dense: true,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.labelLarge),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.joining});
  final bool joining;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: joining ? null : () => _showJoinDialog(context),
      icon: joining
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add, size: 18),
      label: const Text('Join'),
    );
  }

  void _showJoinDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => const _JoinDialog(),
    );
  }
}

class _JoinDialog extends ConsumerStatefulWidget {
  const _JoinDialog();

  @override
  ConsumerState<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends ConsumerState<_JoinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join a cluster'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Invite code',
          hintText: 'e.g. FOGBLT',
        ),
        textCapitalization: TextCapitalization.characters,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            ref
                .read(communitiesProvider.notifier)
                .joinByInviteCode(_controller.text);
            Navigator.of(context).pop();
          },
          child: const Text('Join'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_queue,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No clusters nearby',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Enable location sharing to discover clusters in your area, '
              'or join one with an invite code.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClusterDetail extends ConsumerStatefulWidget {
  const _ClusterDetail({required this.cluster});
  final ClusterModel cluster;

  @override
  ConsumerState<_ClusterDetail> createState() => _ClusterDetailState();
}

class _ClusterDetailState extends ConsumerState<_ClusterDetail>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cluster = widget.cluster;
    return SizedBox(
      height: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Chat'),
              Tab(text: 'Members'),
              Tab(text: 'Challenges'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ChatTab(cluster: cluster),
                _MembersTab(members: cluster.members),
                _ChallengesTab(challenges: cluster.challenges),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat tab ──────────────────────────────────────────────────────────────────

class _ChatTab extends ConsumerStatefulWidget {
  const _ChatTab({required this.cluster});
  final ClusterModel cluster;

  @override
  ConsumerState<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<_ChatTab> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.cluster.messages;
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const Center(child: Text('No messages yet'))
              : ListView.separated(
                  reverse: true,
                  itemCount: messages.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final msg = messages[messages.length - 1 - index];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text(
                          msg.authorName.isNotEmpty ? msg.authorName[0] : '?',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      title: Text(
                        msg.authorName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(msg.content),
                      trailing: msg.reactions.isEmpty
                          ? null
                          : Text(
                              msg.reactions.entries
                                  .map((e) => '${e.key}${e.value}')
                                  .join(' '),
                              style: const TextStyle(fontSize: 12),
                            ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Announce something…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () {
                  final text = _controller.text.trim();
                  if (text.isEmpty) return;
                  ref.read(communitiesProvider.notifier).postMessage(text);
                  _controller.clear();
                },
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Members tab ───────────────────────────────────────────────────────────────

class _MembersTab extends StatelessWidget {
  const _MembersTab({required this.members});
  final List<ClusterMember> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Center(child: Text('No members'));
    }
    return ListView.separated(
      itemCount: members.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final m = members[index];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            child: Text(
              m.displayName.isNotEmpty ? m.displayName[0] : '?',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          title: Text(
            m.isCurrentUser ? '${m.displayName} (you)' : m.displayName,
          ),
          subtitle: Text(
            '${m.stationCount} station${m.stationCount == 1 ? '' : 's'}',
          ),
          trailing: Text(
            'Joined ${_daysAgo(m.joinedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }

  String _daysAgo(DateTime dt) {
    final d = DateTime.now().difference(dt).inDays;
    return d == 0 ? 'today' : '$d d ago';
  }
}

// ── Challenges tab ────────────────────────────────────────────────────────────

class _ChallengesTab extends StatelessWidget {
  const _ChallengesTab({required this.challenges});
  final List<ClusterChallenge> challenges;

  @override
  Widget build(BuildContext context) {
    if (challenges.isEmpty) {
      return const Center(child: Text('No active challenges'));
    }
    return ListView.separated(
      itemCount: challenges.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final c = challenges[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.title,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    c.type.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: c.progressFraction),
              const SizedBox(height: 2),
              Text(
                '${(c.progressFraction * 100).toStringAsFixed(0)} % — '
                '${c.status.label}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
