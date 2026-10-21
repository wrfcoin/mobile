import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/weather_narrative.dart';

/// Card displaying a single weather narrative.
///
/// Records get celebratory styling (gold border, star icon).
/// Events get storm-colored accents. Streaks get fire accents.
class NarrativeCard extends StatelessWidget {
  final WeatherNarrative narrative;
  final VoidCallback? onShare;

  const NarrativeCard({super.key, required this.narrative, this.onShare});

  @override
  Widget build(BuildContext context) {
    final isRecord = narrative.type == NarrativeType.record;
    final isEvent = narrative.type == NarrativeType.event;
    final isStreak = narrative.type == NarrativeType.streak;

    final accentColor = isRecord
        ? const Color(0xFFFFD700) // Gold for records
        : isEvent
        ? const Color(0xFF845EF7) // Purple for events
        : isStreak
        ? const Color(0xFFFF6B6B) // Red-orange for streaks
        : AppColors.primary; // Teal for digests

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isRecord
            ? BorderSide(color: accentColor.withValues(alpha: 0.5), width: 1.5)
            : BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Type icon with accent background
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(narrative.icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isRecord) ...[
                            Icon(Icons.star, color: accentColor, size: 14),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              narrative.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isRecord ? accentColor : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('MMM d, yyyy').format(narrative.date),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Type badge
                _TypeBadge(type: narrative.type, color: accentColor),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              narrative.description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            if (narrative.isShareable && onShare != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ActionChip(
                  avatar: const Icon(Icons.share, size: 14),
                  label: const Text('Share'),
                  onPressed: onShare,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final NarrativeType type;
  final Color color;

  const _TypeBadge({required this.type, required this.color});

  String get _label {
    switch (type) {
      case NarrativeType.record:
        return 'Record';
      case NarrativeType.event:
        return 'Event';
      case NarrativeType.streak:
        return 'Streak';
      case NarrativeType.digest:
        return 'Digest';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
