import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:wrfcoin_mobile/features/analytics/data/analytics_calculations.dart';
import 'package:wrfcoin_mobile/features/analytics/data/analytics_models.dart';
import 'package:wrfcoin_mobile/features/analytics/services/analytics_export_service.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';

void main() {
  test('buildAnalyticsSnapshot aggregates density and earnings trends', () {
    final readings = [
      AnalyticsReadingSample(
        timestamp: DateTime(2026, 4, 8, 8, 30),
        latitude: 37.7749,
        longitude: -122.4194,
        pressureHpa: 1012.2,
        synced: true,
      ),
      AnalyticsReadingSample(
        timestamp: DateTime(2026, 4, 8, 12, 15),
        latitude: 37.7751,
        longitude: -122.4191,
        pressureHpa: 1011.8,
        synced: false,
      ),
      AnalyticsReadingSample(
        timestamp: DateTime(2026, 4, 9, 9, 0),
        latitude: 37.7762,
        longitude: -122.4182,
        pressureHpa: 1010.9,
        synced: true,
      ),
    ];

    final validationEvents = [
      CollectorValidationEvent(
        timestamp: DateTime(2026, 4, 8, 13, 0),
        code: 'sync_success',
        message:
            'accepted=2, failed=0, pending=0, rewardTotalsAvailable=true, rewardWrfTotal=6.50',
      ),
      CollectorValidationEvent(
        timestamp: DateTime(2026, 4, 9, 13, 0),
        code: 'sync_partial',
        message:
            'accepted=1, failed=1, pending=1, rewardTotalsAvailable=false, rewardWrfTotal=0',
      ),
    ];

    final snapshot = buildAnalyticsSnapshot(
      readings: readings,
      validationEvents: validationEvents,
      syncedSubmissionCount: 3,
      earnedRewardWrf: 6.5,
      rewardTotalsAvailable: true,
      generatedAt: DateTime(2026, 4, 10, 10, 0),
    );

    expect(snapshot.summary.totalReadings, 3);
    expect(snapshot.summary.syncedReadings, 2);
    expect(snapshot.summary.pendingReadings, 1);
    expect(snapshot.summary.earnedWrf, 6.5);
    expect(snapshot.summary.heatmapPeakCount, greaterThan(0));
    expect(snapshot.collectionTrend.map((point) => point.value).toList(), [
      2,
      1,
    ]);
    expect(snapshot.earningTrend.map((point) => point.value).toList(), [
      6.5,
      2.1666666666666665,
    ]);
    expect(snapshot.readings.first.heatmapRow, isNonNegative);
    expect(snapshot.readings.first.heatmapColumn, isNonNegative);
    expect(snapshot.readings.first.dailyCollectionCount, 2);
    expect(snapshot.readings.first.dailyEarnedWrf, 6.5);
  });

  test('AnalyticsExportService builds CSV and JSON exports', () {
    final snapshot = buildAnalyticsSnapshot(
      readings: [
        AnalyticsReadingSample(
          timestamp: DateTime(2026, 4, 8, 8, 30),
          latitude: 37.7749,
          longitude: -122.4194,
          pressureHpa: 1012.2,
          synced: true,
        ),
      ],
      validationEvents: const [],
      syncedSubmissionCount: 1,
      earnedRewardWrf: 1.25,
      rewardTotalsAvailable: false,
      generatedAt: DateTime(2026, 4, 10, 10, 0),
    );

    final service = AnalyticsExportService();
    final csv = service.buildCsv(snapshot);
    final jsonPayload = service.buildJson(snapshot);
    final decoded = jsonDecode(jsonPayload) as Map<String, dynamic>;

    expect(csv, contains('timestamp,latitude,longitude,pressure_hpa'));
    expect(csv, contains('2026-04-08T08:30:00.000'));
    expect(decoded['summary'], isA<Map<String, dynamic>>());
    expect(decoded['readings'], isA<List<dynamic>>());
    expect(decoded['generatedAt'], '2026-04-10T10:00:00.000');
  });
}
