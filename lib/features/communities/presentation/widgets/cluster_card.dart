import 'package:flutter/material.dart';

import '../../data/models/cluster_model.dart';

/// Compact card representing a [ClusterModel] in the discovery / joined list.
class ClusterCard extends StatelessWidget {
  const ClusterCard({
    required this.cluster,
    this.onTap,
    this.selected = false,
    super.key,
  });

  final ClusterModel cluster;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _Avatar(name: cluster.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cluster.name,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (cluster.isMember)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Chip(
                              label: const Text('Joined'),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSecondaryContainer,
                              ),
                              backgroundColor: colorScheme.secondaryContainer,
                              padding: EdgeInsets.zero,
                              side: BorderSide.none,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cluster.description,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${cluster.memberCount} member${cluster.memberCount == 1 ? '' : 's'}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.location_on_outlined, size: 14),
                        const SizedBox(width: 4),
                        Text(cluster.geohash, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 22,
      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
