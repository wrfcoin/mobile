import '../../weather/domain/models/coarse_location.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../data/analytics_models.dart';

class AnalyticsExportService {
  const AnalyticsExportService();

  Future<void> shareCsv(AnalyticsSnapshot snapshot) {
    return _shareFile(
      snapshot,
      fileName: 'wrfcoin-analytics.csv',
      mimeType: 'text/csv',
      content: buildCsv(snapshot),
    );
  }

  Future<void> shareJson(AnalyticsSnapshot snapshot) {
    return _shareFile(
      snapshot,
      fileName: 'wrfcoin-analytics.json',
      mimeType: 'application/json',
      content: buildJson(snapshot),
    );
  }

  String buildCsv(AnalyticsSnapshot snapshot) {
    final buffer = StringBuffer();
    buffer.writeln(
      'timestamp,latitude,longitude,pressure_hpa,synced,heatmap_row,heatmap_column,daily_collection_count,daily_earned_wrf',
    );

    for (final reading in snapshot.readings) {
      buffer.writeln(
        [
          reading.timestamp.toIso8601String(),
          CoarseLocation.coarsen(reading.latitude).toStringAsFixed(1),
          CoarseLocation.coarsen(reading.longitude).toStringAsFixed(1),
          reading.pressureHpa.toStringAsFixed(2),
          reading.synced,
          reading.heatmapRow,
          reading.heatmapColumn,
          reading.dailyCollectionCount,
          reading.dailyEarnedWrf.toStringAsFixed(4),
        ].map(_csvValue).join(','),
      );
    }

    return buffer.toString();
  }

  String buildJson(AnalyticsSnapshot snapshot) {
    final payload = <String, dynamic>{
      'generatedAt': snapshot.generatedAt.toIso8601String(),
      'summary': {
        'totalReadings': snapshot.summary.totalReadings,
        'syncedReadings': snapshot.summary.syncedReadings,
        'pendingReadings': snapshot.summary.pendingReadings,
        'earnedWrf': snapshot.summary.earnedWrf,
        'rewardTotalsAvailable': snapshot.summary.rewardTotalsAvailable,
        'averagePressureHpa': snapshot.summary.averagePressureHpa,
        'firstReadingAt': snapshot.summary.firstReadingAt?.toIso8601String(),
        'lastReadingAt': snapshot.summary.lastReadingAt?.toIso8601String(),
        'heatmapPeakCount': snapshot.summary.heatmapPeakCount,
      },
      'collectionTrend': snapshot.collectionTrend
          .map(
            (point) => {
              'day': point.day.toIso8601String(),
              'value': point.value,
            },
          )
          .toList(growable: false),
      'earningTrend': snapshot.earningTrend
          .map(
            (point) => {
              'day': point.day.toIso8601String(),
              'value': point.value,
            },
          )
          .toList(growable: false),
      'heatmap': snapshot.heatmapBins
          .map(
            (bin) => {'row': bin.row, 'column': bin.column, 'count': bin.count},
          )
          .toList(growable: false),
      'readings': snapshot.readings
          .map(
            (reading) => {
              'timestamp': reading.timestamp.toIso8601String(),
              // Defensive: a snapshot built elsewhere may carry finer positions.
              'latitude': CoarseLocation.coarsen(reading.latitude),
              'longitude': CoarseLocation.coarsen(reading.longitude),
              'pressureHpa': reading.pressureHpa,
              'synced': reading.synced,
              'heatmapRow': reading.heatmapRow,
              'heatmapColumn': reading.heatmapColumn,
              'dailyCollectionCount': reading.dailyCollectionCount,
              'dailyEarnedWrf': reading.dailyEarnedWrf,
            },
          )
          .toList(growable: false),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> _shareFile(
    AnalyticsSnapshot snapshot, {
    required String fileName,
    required String mimeType,
    required String content,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
        text:
            'WRFCoin analytics export generated ${snapshot.generatedAt.toLocal()}',
      ),
    );
  }

  String _csvValue(Object? value) {
    final text = value?.toString() ?? '';
    final needsQuotes =
        text.contains(',') || text.contains('"') || text.contains('\n');
    final escaped = text.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }
}
