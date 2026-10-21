import '../../weather/domain/models/coarse_location.dart';

import 'dart:math' as math;

import '../../collector/data/services/collector_preferences.dart';
import 'analytics_models.dart';

const int analyticsHeatmapSize = 6;

AnalyticsSnapshot buildAnalyticsSnapshot({
  required List<AnalyticsReadingSample> readings,
  required List<CollectorValidationEvent> validationEvents,
  required int syncedSubmissionCount,
  required double earnedRewardWrf,
  required bool rewardTotalsAvailable,
  DateTime? generatedAt,
}) {
  final generated = generatedAt ?? DateTime.now();
  // Coarsen first, so the heatmap and every derived value only ever see the 0.1 degree grid.
  final sortedReadings = [
    for (final r in readings)
      AnalyticsReadingSample(
        timestamp: r.timestamp,
        latitude: CoarseLocation.coarsen(r.latitude),
        longitude: CoarseLocation.coarsen(r.longitude),
        pressureHpa: r.pressureHpa,
        synced: r.synced,
      ),
  ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final collectionCounts = <DateTime, int>{};
  for (final reading in sortedReadings) {
    final day = _dayKey(reading.timestamp);
    collectionCounts[day] = (collectionCounts[day] ?? 0) + 1;
  }

  final syncEventMetrics = _extractSyncMetrics(validationEvents);
  final earningsByDay = <DateTime, double>{};
  final estimatedPerReading = syncedSubmissionCount > 0
      ? earnedRewardWrf / syncedSubmissionCount
      : 0.0;

  for (final event in syncEventMetrics) {
    final day = _dayKey(event.timestamp);
    final fallbackEarning = event.acceptedCount * estimatedPerReading;
    final earnedValue = event.rewardTotalsAvailable && event.rewardWrfTotal > 0
        ? event.rewardWrfTotal
        : fallbackEarning;
    earningsByDay[day] = (earningsByDay[day] ?? 0) + earnedValue;
  }

  if (earningsByDay.isEmpty && collectionCounts.isNotEmpty) {
    for (final day in collectionCounts.keys) {
      earningsByDay[day] = 0;
    }
  }

  final heatmapPlacements = _assignHeatmapPlacements(sortedReadings);
  final heatmapCounts = <String, int>{};
  for (final placement in heatmapPlacements) {
    final key = '${placement.row}:${placement.column}';
    heatmapCounts[key] = (heatmapCounts[key] ?? 0) + 1;
  }

  final heatmapBins = <AnalyticsHeatmapBin>[];
  var peakCount = 0;
  for (var row = 0; row < analyticsHeatmapSize; row++) {
    for (var column = 0; column < analyticsHeatmapSize; column++) {
      final count = heatmapCounts['$row:$column'] ?? 0;
      peakCount = math.max(peakCount, count);
      heatmapBins.add(
        AnalyticsHeatmapBin(row: row, column: column, count: count),
      );
    }
  }

  final enrichedReadings = <AnalyticsReadingSample>[];
  for (var index = 0; index < sortedReadings.length; index++) {
    final reading = sortedReadings[index];
    final placement = heatmapPlacements[index];
    final day = _dayKey(reading.timestamp);
    enrichedReadings.add(
      AnalyticsReadingSample(
        timestamp: reading.timestamp,
        // Positions leave this function on the 0.1 degree grid whatever the caller passed.
        latitude: CoarseLocation.coarsen(reading.latitude),
        longitude: CoarseLocation.coarsen(reading.longitude),
        pressureHpa: reading.pressureHpa,
        synced: reading.synced,
        heatmapRow: placement.row,
        heatmapColumn: placement.column,
        dailyCollectionCount: collectionCounts[day] ?? 0,
        dailyEarnedWrf: earningsByDay[day] ?? 0,
      ),
    );
  }

  final collectionTrend =
      collectionCounts.entries
          .map(
            (entry) => AnalyticsTrendPoint(
              day: entry.key,
              value: entry.value.toDouble(),
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => a.day.compareTo(b.day));

  final earningTrend =
      earningsByDay.entries
          .map(
            (entry) => AnalyticsTrendPoint(day: entry.key, value: entry.value),
          )
          .toList(growable: false)
        ..sort((a, b) => a.day.compareTo(b.day));

  final averagePressureHpa = sortedReadings.isEmpty
      ? 0.0
      : sortedReadings
                .map((reading) => reading.pressureHpa)
                .reduce((a, b) => a + b) /
            sortedReadings.length;
  final summary = AnalyticsSummary(
    totalReadings: sortedReadings.length,
    syncedReadings: sortedReadings.where((reading) => reading.synced).length,
    pendingReadings: sortedReadings.where((reading) => !reading.synced).length,
    earnedWrf: rewardTotalsAvailable
        ? earnedRewardWrf
        : earningsByDay.values.fold(0.0, (a, b) => a + b),
    rewardTotalsAvailable: rewardTotalsAvailable,
    averagePressureHpa: averagePressureHpa,
    firstReadingAt: sortedReadings.isEmpty
        ? null
        : sortedReadings.first.timestamp,
    lastReadingAt: sortedReadings.isEmpty
        ? null
        : sortedReadings.last.timestamp,
    heatmapPeakCount: peakCount,
  );

  return AnalyticsSnapshot(
    summary: summary,
    readings: enrichedReadings,
    heatmapBins: heatmapBins,
    collectionTrend: collectionTrend,
    earningTrend: earningTrend,
    generatedAt: generated,
  );
}

DateTime _dayKey(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

class _HeatmapPlacement {
  final int row;
  final int column;

  const _HeatmapPlacement({required this.row, required this.column});
}

class _SyncMetrics {
  final DateTime timestamp;
  final int acceptedCount;
  final double rewardWrfTotal;
  final bool rewardTotalsAvailable;

  const _SyncMetrics({
    required this.timestamp,
    required this.acceptedCount,
    required this.rewardWrfTotal,
    required this.rewardTotalsAvailable,
  });
}

List<_HeatmapPlacement> _assignHeatmapPlacements(
  List<AnalyticsReadingSample> readings,
) {
  if (readings.isEmpty) return const [];

  var minLat = readings.first.latitude;
  var maxLat = readings.first.latitude;
  var minLng = readings.first.longitude;
  var maxLng = readings.first.longitude;

  for (final reading in readings.skip(1)) {
    minLat = math.min(minLat, reading.latitude);
    maxLat = math.max(maxLat, reading.latitude);
    minLng = math.min(minLng, reading.longitude);
    maxLng = math.max(maxLng, reading.longitude);
  }

  final latRange = (maxLat - minLat).abs();
  final lngRange = (maxLng - minLng).abs();

  return readings
      .map((reading) {
        final row = latRange < 1e-9
            ? analyticsHeatmapSize ~/ 2
            : ((maxLat - reading.latitude) /
                      latRange *
                      (analyticsHeatmapSize - 1))
                  .round()
                  .clamp(0, analyticsHeatmapSize - 1);
        final column = lngRange < 1e-9
            ? analyticsHeatmapSize ~/ 2
            : ((reading.longitude - minLng) /
                      lngRange *
                      (analyticsHeatmapSize - 1))
                  .round()
                  .clamp(0, analyticsHeatmapSize - 1);

        return _HeatmapPlacement(row: row, column: column);
      })
      .toList(growable: false);
}

List<_SyncMetrics> _extractSyncMetrics(
  List<CollectorValidationEvent> validationEvents,
) {
  return validationEvents
      .where((event) => event.code.startsWith('sync_'))
      .map((event) {
        final values = _parseKeyValues(event.message);
        return _SyncMetrics(
          timestamp: event.timestamp,
          acceptedCount: int.tryParse(values['accepted'] ?? '') ?? 0,
          rewardWrfTotal: double.tryParse(values['rewardWrfTotal'] ?? '') ?? 0,
          rewardTotalsAvailable:
              (values['rewardTotalsAvailable'] ?? '').toLowerCase() == 'true',
        );
      })
      .toList(growable: false);
}

Map<String, String> _parseKeyValues(String message) {
  final pairs = <String, String>{};
  for (final part in message.split(',')) {
    final trimmed = part.trim();
    final equalsIndex = trimmed.indexOf('=');
    if (equalsIndex <= 0) continue;
    final key = trimmed.substring(0, equalsIndex).trim();
    final value = trimmed.substring(equalsIndex + 1).trim();
    pairs[key] = value;
  }
  return pairs;
}
