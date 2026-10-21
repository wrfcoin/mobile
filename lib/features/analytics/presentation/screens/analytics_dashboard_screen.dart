import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../data/analytics_models.dart';
import '../../services/analytics_export_service.dart';
import '../providers/analytics_provider.dart';
import '../widgets/analytics_trend_chart.dart';
import '../widgets/collection_heatmap_widget.dart';

class AnalyticsDashboardScreen extends ConsumerStatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  ConsumerState<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState
    extends ConsumerState<AnalyticsDashboardScreen> {
  bool _exportingCsv = false;
  bool _exportingJson = false;

  Future<void> _refresh() async {
    ref.invalidate(analyticsSnapshotProvider);
    await ref.read(analyticsSnapshotProvider.future);
  }

  Future<void> _shareCsv(AnalyticsSnapshot snapshot) async {
    if (_exportingCsv) return;
    setState(() => _exportingCsv = true);
    try {
      await const AnalyticsExportService().shareCsv(snapshot);
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _shareJson(AnalyticsSnapshot snapshot) async {
    if (_exportingJson) return;
    setState(() => _exportingJson = true);
    try {
      await const AnalyticsExportService().shareJson(snapshot);
    } finally {
      if (mounted) setState(() => _exportingJson = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(analyticsSnapshotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh analytics',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(),
          ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Building local density and earnings analytics...',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              SizedBox(height: 16),
              Expanded(child: ShimmerList(count: 4, height: 120)),
            ],
          ),
        ),
        error: (error, _) => AppErrorWidget(
          title: 'Analytics unavailable',
          message: error.toString(),
          onRetry: () => _refresh(),
        ),
        data: (snapshot) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (kIsWeb)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      color: AppColors.warning.withValues(alpha: 0.14),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: AppColors.warning),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Analytics export is best supported on the mobile app.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                _SummaryGrid(snapshot: snapshot),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Collection Density',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Heatmap bins are built from local latitude and longitude clusters.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        CollectionHeatmapWidget(
                          bins: snapshot.heatmapBins,
                          peakCount: snapshot.summary.heatmapPeakCount,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AnalyticsTrendChart(
                              title: 'Collection Trend',
                              subtitle: 'Daily reading volume from locally stored sensor samples.',
                              points: snapshot.collectionTrend,
                              lineColor: AppColors.primary,
                              valueSuffix: ' readings',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: AnalyticsTrendChart(
                              title: 'Earnings Trend',
                              subtitle: snapshot.summary.rewardTotalsAvailable
                                  ? 'Daily WRF credited from sync events.'
                                  : 'Estimated from accepted sync events until backend reward totals are available.',
                              points: snapshot.earningTrend,
                              lineColor: AppColors.success,
                              valueSuffix: ' WRF',
                            ),
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        AnalyticsTrendChart(
                          title: 'Collection Trend',
                          subtitle: 'Daily reading volume from locally stored sensor samples.',
                          points: snapshot.collectionTrend,
                          lineColor: AppColors.primary,
                          valueSuffix: ' readings',
                        ),
                        const SizedBox(height: 16),
                        AnalyticsTrendChart(
                          title: 'Earnings Trend',
                          subtitle: snapshot.summary.rewardTotalsAvailable
                              ? 'Daily WRF credited from sync events.'
                              : 'Estimated from accepted sync events until backend reward totals are available.',
                          points: snapshot.earningTrend,
                          lineColor: AppColors.success,
                          valueSuffix: ' WRF',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Export',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Share CSV or JSON analytics snapshots with your own tools.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: kIsWeb || _exportingCsv
                                  ? null
                                  : () => _shareCsv(snapshot),
                              icon: _exportingCsv
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.table_chart_outlined),
                              label: const Text('Export CSV'),
                            ),
                            OutlinedButton.icon(
                              onPressed: kIsWeb || _exportingJson
                                  ? null
                                  : () => _shareJson(snapshot),
                              icon: _exportingJson
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.data_object),
                              label: const Text('Export JSON'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Updated ${DateFormat('MMM d, h:mm a').format(snapshot.generatedAt.toLocal())}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final summary = snapshot.summary;
    final cards = [
      _SummaryCard(
        label: 'Readings',
        value: '${summary.totalReadings}',
        icon: Icons.sensors,
      ),
      _SummaryCard(
        label: 'Synced',
        value: '${summary.syncedReadings}',
        icon: Icons.cloud_done,
      ),
      _SummaryCard(
        label: 'Pending',
        value: '${summary.pendingReadings}',
        icon: Icons.cloud_off,
      ),
      _SummaryCard(
        label: summary.rewardTotalsAvailable ? 'WRF earned' : 'Estimated WRF',
        value: summary.earnedWrf.toStringAsFixed(2),
        icon: Icons.currency_exchange,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: _cardWidth(constraints.maxWidth, columnCount),
                  child: card,
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  double _cardWidth(double maxWidth, int columns) {
    if (columns == 1) return maxWidth;
    final spacing = 12.0 * (columns - 1);
    return (maxWidth - spacing) / columns;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
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
