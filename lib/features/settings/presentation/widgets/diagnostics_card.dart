import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../services/observability/crash_report_store.dart';

typedef ShareCrashReports = Future<void> Function(
  List<XFile> files,
  Rect origin,
);

final shareCrashReportsProvider = Provider<ShareCrashReports>(
  (ref) => (files, origin) async {
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        fileNameOverrides: files.map((f) => f.name).toList(),
        subject: 'WRFCoin crash reports',
        sharePositionOrigin: origin,
      ),
    );
  },
);

class DiagnosticsCard extends ConsumerStatefulWidget {
  const DiagnosticsCard({super.key});

  @override
  ConsumerState<DiagnosticsCard> createState() => _DiagnosticsCardState();
}

class _DiagnosticsCardState extends ConsumerState<DiagnosticsCard> {
  bool _busy = false;

  Future<void> _act({required bool share}) async {
    setState(() => _busy = true);
    try {
      final store = await ref.read(localCrashReportStoreProvider.future);
      if (!mounted || store == null) return;
      if (share) {
        final files = await store.exportFiles();
        if (!mounted || files.isEmpty) return;
        final box = context.findRenderObject() as RenderBox?;
        final origin = box == null
            ? const Rect.fromLTWH(0, 0, 1, 1)
            : box.localToGlobal(Offset.zero) & box.size;
        await ref.read(shareCrashReportsProvider)(files, origin);
      } else {
        await store.clear();
      }
      if (mounted) ref.invalidate(localCrashReportCountProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not access crash reports. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(localCrashReportCountProvider);
    final enabled = !_busy && (count.value ?? 0) > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              count.when(
                data: (n) => n == null
                    ? 'Local crash reports are unavailable on this platform.'
                    : '$n crash ${n == 1 ? 'report' : 'reports'} on this device',
                loading: () => 'Loading crash reports…',
                error: (_, _) => 'Local crash reports are unavailable.',
              ),
            ),
            const Text(
              'Reports stay on this device. Nothing is sent until you choose Share.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: enabled ? () => _act(share: true) : null,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share crash reports'),
                ),
                TextButton.icon(
                  onPressed: enabled ? () => _act(share: false) : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete crash reports'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
