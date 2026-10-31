import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Local date and time for allowlist cooldowns, e.g. "Sun 2 Nov, 14:05".
String formatAllowlistTime(DateTime time) =>
    DateFormat('EEE d MMM, HH:mm').format(time.toLocal());

enum SafetyTone { info, caution, blocked }

/// A calm boxed note. [SafetyTone.blocked] is for Send refusals only.
class SafetyNotice extends StatelessWidget {
  const SafetyNotice({
    super.key,
    required this.title,
    this.body,
    this.tone = SafetyTone.info,
    this.icon,
    this.children = const [],
  });

  final String title;
  final String? body;
  final SafetyTone tone;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color fg, Color bg, IconData fallback) = switch (tone) {
      SafetyTone.info => (
        scheme.primary,
        scheme.primaryContainer.withValues(alpha: 0.35),
        Icons.info_outline,
      ),
      SafetyTone.caution => (
        scheme.tertiary,
        scheme.tertiaryContainer.withValues(alpha: 0.45),
        Icons.shield_outlined,
      ),
      SafetyTone.blocked => (
        scheme.error,
        scheme.errorContainer.withValues(alpha: 0.45),
        Icons.block,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? fallback, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (body != null) ...[const SizedBox(height: 4), Text(body!)],
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
