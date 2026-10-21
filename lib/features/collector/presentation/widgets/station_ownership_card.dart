import 'package:flutter/material.dart';

/// Entry points for the station-owner actions (security, transfer, accept).
/// The buttons sit on their own row under the text: as a ListTile `trailing`
/// they took the full width on a phone and squeezed the title to one
/// character per line.
class StationOwnershipCard extends StatelessWidget {
  const StationOwnershipCard({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Station ownership',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Give your station away or accept one.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => onNavigate('/collect/station-security'),
                  child: const Text('Security'),
                ),
                TextButton(
                  onPressed: () => onNavigate('/collect/station-transfer'),
                  child: const Text('Transfer'),
                ),
                TextButton(
                  onPressed: () => onNavigate('/collect/station-accept'),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
