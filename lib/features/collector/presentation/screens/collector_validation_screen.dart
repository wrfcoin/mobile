import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/storage/local_db.dart';
import '../../data/repositories/collector_repository_impl.dart';
import '../../data/services/collector_preferences.dart';
import '../providers/collector_provider.dart';

class CollectorValidationScreen extends ConsumerStatefulWidget {
  const CollectorValidationScreen({super.key});

  @override
  ConsumerState<CollectorValidationScreen> createState() =>
      _CollectorValidationScreenState();
}

class _CollectorValidationScreenState
    extends ConsumerState<CollectorValidationScreen> {
  late Future<List<CollectorValidationEvent>> _eventsFuture;
  late Future<(List<SensorReading>, List<CollectionRun>)> _historyFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _loadEvents();
    _historyFuture = _loadHistory();
  }

  Future<(List<SensorReading>, List<CollectionRun>)> _loadHistory() async {
    final store = ref.read(collectorRepositoryProvider).db;
    return (
      await store.getRecentReadings(limit: 20),
      await store.getCollectionRuns(limit: 40),
    );
  }

  Future<List<CollectorValidationEvent>> _loadEvents() {
    return ref.read(collectorPreferencesProvider).loadValidationEvents();
  }

  Future<void> _refresh() async {
    setState(() {
      _eventsFuture = _loadEvents();
      _historyFuture = _loadHistory();
    });
  }

  Future<void> _runCollectNow() async {
    await ref.read(collectorProvider.notifier).collectNow();
    await _refresh();
  }

  Future<void> _runSyncNow() async {
    await ref.read(collectorProvider.notifier).syncPendingData();
    await _refresh();
  }

  Future<void> _clearLog() async {
    await ref.read(collectorProvider.notifier).clearValidationEvents();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectorProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collector Validation'),
        actions: [
          IconButton(
            tooltip: 'Refresh validation log',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'Clear validation log',
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FutureBuilder<(List<SensorReading>, List<CollectionRun>)>(
              future: _historyFuture,
              builder: (context, snapshot) {
                final (readings, runs) =
                    snapshot.data ?? (const <SensorReading>[], const <CollectionRun>[]);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HistoryCard(
                      title: 'Recent readings',
                      empty: 'No readings saved.',
                      rows: [
                        for (final reading in readings)
                          (
                            _formatDateTime(reading.timestamp),
                            [
                              reading.source ?? 'from before sources',
                              if (reading.locationSource != null)
                                '${reading.locationSource} location',
                              reading.synced ? 'uploaded' : 'waiting',
                            ].join(', '),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _HistoryCard(
                      title: 'Recent runs',
                      empty: 'No runs recorded.',
                      rows: [
                        for (final run in runs)
                          (
                            _formatDateTime(run.startedAt),
                            '${run.kind}: ${run.outcome}'
                                '${run.acceptedCount > 0 ? ' (${run.acceptedCount})' : ''}'
                                '${run.detail == null ? '' : ' (${run.detail})'}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Loop Snapshot',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SummaryRow(
                      label: 'Pending queue',
                      value: '${state.pendingSyncCount}',
                    ),
                    const SizedBox(height: 8),
                    _SummaryRow(
                      label: 'Synced submissions',
                      value: '${state.syncedSubmissionCount}',
                    ),
                    const SizedBox(height: 8),
                    _SummaryRow(
                      label: 'Last submission',
                      value: state.lastSubmissionId ?? 'None yet',
                    ),
                    const SizedBox(height: 8),
                    _SummaryRow(
                      label: 'Backend status',
                      value: state.lastSubmissionStatus ?? 'Unknown',
                    ),
                    const SizedBox(height: 8),
                    _SummaryRow(
                      label: 'Last sync attempt',
                      value: state.lastSyncAttemptAt == null
                          ? 'Never'
                          : _formatDateTime(state.lastSyncAttemptAt!),
                    ),
                    if (state.syncMessage != null) ...[
                      const SizedBox(height: 8),
                      _SummaryRow(
                        label: 'Last sync message',
                        value: state.syncMessage!,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: state.isCollectingNow || state.isSyncing
                              ? null
                              : _runCollectNow,
                          icon: state.isCollectingNow
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sensors),
                          label: const Text('Collect now'),
                        ),
                        OutlinedButton.icon(
                          onPressed: state.isSyncing ? null : _runSyncNow,
                          icon: state.isSyncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Sync pending'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Validation Log',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<CollectorValidationEvent>>(
              future: _eventsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final events = snapshot.data!;
                if (events.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No validation events recorded yet. Run a collect or sync cycle on-device to populate this log.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }

                return Column(
                  children: events
                      .map(
                        (event) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: ListTile(
                              title: Text(event.code),
                              subtitle: Text(event.message),
                              trailing: Text(
                                _formatDateTime(event.timestamp),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// A short log, readable on any build of the app.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.title,
    required this.empty,
    required this.rows,
  });

  final String title;
  final String empty;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text(
                empty,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            for (final (time, what) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(what),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
