import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shadow_alerts_controller.dart';

class ShadowAlertsScreen extends ConsumerWidget {
  const ShadowAlertsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(shadowAlertsEnabledProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Research alerts')),
        body: const Center(child: Text('Research alerts are disabled.')),
      );
    }
    return _ShadowAlertsView(
      controller: ref.watch(shadowAlertsControllerProvider),
    );
  }
}

class _ShadowAlertsView extends StatefulWidget {
  const _ShadowAlertsView({required this.controller});
  final ShadowAlertsController controller;
  @override
  State<_ShadowAlertsView> createState() => _ShadowAlertsViewState();
}

class _ShadowAlertsViewState extends State<_ShadowAlertsView> {
  final area = TextEditingController();
  Set<String> selected = {'rain', 'heat', 'wind'};
  bool hydrated = false;
  String? validation;
  @override
  void initState() {
    super.initState();
    widget.controller.start().then((_) {
      if (mounted && !hydrated) {
        setState(() {
          area.text = widget.controller.cell;
          selected = Set.of(widget.controller.hazards);
          hydrated = true;
        });
      }
    });
  }

  @override
  void dispose() {
    area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(title: const Text('Research alerts')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  color: colors.secondaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shadow preview',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Advisory research, not an official warning. Follow your national weather service. Updates appear only while this screen is open. No SMS or push is sent.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Your research subscription',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: area,
                  decoration: InputDecoration(
                    labelText: 'Coarse area cell',
                    hintText: '0.0,36.0',
                    helperText:
                        'One decimal per coordinate; no precise location.',
                    errorText: validation,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['rain', 'heat', 'wind']
                      .map(
                        (h) => FilterChip(
                          label: Text(h[0].toUpperCase() + h.substring(1)),
                          selected: selected.contains(h),
                          onSelected: (on) => setState(() {
                            on ? selected.add(h) : selected.remove(h);
                          }),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await c.save(area.text.trim(), selected);
                      if (mounted) setState(() => validation = null);
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => validation =
                              'Enter a valid coarse cell and select a hazard.',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save on this device'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Latest research events',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (c.loading) const LinearProgressIndicator(),
                if (c.error != null)
                  Text(c.error!, style: TextStyle(color: colors.error)),
                if (!c.loading && c.events.isEmpty && c.error == null)
                  const Text(
                    'No matching research events. This is not an all-clear.',
                  ),
                for (final event in c.events)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                event['status'] == 'suppressed_by_official'
                                    ? Icons.verified_outlined
                                    : Icons.science_outlined,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  event['status'] == 'suppressed_by_official'
                                      ? 'Official warning takes precedence'
                                      : 'WRFCoin research advisory',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('${event['hazard']} • ${event['cell']}'),
                          Text(
                            'Until ${DateTime.fromMillisecondsSinceEpoch((event['expires'] as num).toInt(), isUtc: true).toIso8601String()}',
                          ),
                          if (event['status'] == 'suppressed_by_official') ...[
                            const Text(
                              'Independent advisory suppressed. Consult the official source:',
                            ),
                            for (final source
                                in (event['official'] as List? ?? []))
                              SelectableText('${source['url']}'),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
