// The analytics exports never carry a reading position finer than 0.1 degree, including for rows
// stored before the ruling. Synthetic positions.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/analytics/data/analytics_calculations.dart';
import 'package:wrfcoin_mobile/features/analytics/data/analytics_models.dart';
import 'package:wrfcoin_mobile/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:wrfcoin_mobile/features/analytics/services/analytics_export_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

void main() {
  test('an OLD 3-decimal row read from SQLite reaches the JSON and CSV exports at 0.1', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // insertReading bypasses the v4 migration, like a row written by a pre-change build.
    await db.insertReading(SensorReadingsCompanion.insert(
      latitude: 10.123,
      longitude: 20.456,
      pressureHpa: 1013.25,
      timestamp: DateTime.utc(2026, 9, 30, 12),
      synced: const Value(true),
    ));
    final rows = await db.select(db.sensorReadings).get();
    expect(rows.single.latitude, 10.123); // really stored fine
    final snapshot = buildAnalyticsSnapshot(
      readings: rows.map(analyticsSampleFromRow).toList(),
      validationEvents: const [],
      syncedSubmissionCount: 1,
      earnedRewardWrf: 0,
      rewardTotalsAvailable: true,
      generatedAt: DateTime.utc(2026, 9, 30, 13),
    );
    final service = AnalyticsExportService();
    final decoded = jsonDecode(service.buildJson(snapshot)) as Map<String, dynamic>;
    final reading = (decoded['readings'] as List).single as Map<String, dynamic>;
    expect(reading['latitude'], 10.1);
    expect(reading['longitude'], 20.5);
    final csvRow = service.buildCsv(snapshot).split('\n')[1].split(',');
    expect(csvRow[1], '10.1');
    expect(csvRow[2], '20.5');
    expect(service.buildJson(snapshot), isNot(contains('10.123')));
    expect(service.buildJson(snapshot), isNot(contains('20.456')));
  });

  test('buildAnalyticsSnapshot coarsens its input, so derived values use the coarse grid', () {
    final snapshot = buildAnalyticsSnapshot(
      readings: [
        AnalyticsReadingSample(
          timestamp: DateTime.utc(2026, 9, 30, 12),
          latitude: 10.123,
          longitude: 20.456,
          pressureHpa: 1000,
          synced: false,
        ),
      ],
      validationEvents: const [],
      syncedSubmissionCount: 0,
      earnedRewardWrf: 0,
      rewardTotalsAvailable: true,
      generatedAt: DateTime.utc(2026, 9, 30, 13),
    );
    expect(snapshot.readings.single.latitude, 10.1);
    expect(snapshot.readings.single.longitude, 20.5);
  });

  test('buildJson coarsens a snapshot built by hand with fine positions', () {
    final base = buildAnalyticsSnapshot(
      readings: [
        AnalyticsReadingSample(
          timestamp: DateTime.utc(2026, 9, 30, 12),
          latitude: 1.0,
          longitude: 2.0,
          pressureHpa: 1000,
          synced: false,
        ),
      ],
      validationEvents: const [],
      syncedSubmissionCount: 0,
      earnedRewardWrf: 0,
      rewardTotalsAvailable: true,
      generatedAt: DateTime.utc(2026, 9, 30, 13),
    );
    final handBuilt = AnalyticsSnapshot(
      generatedAt: base.generatedAt,
      summary: base.summary,
      collectionTrend: base.collectionTrend,
      earningTrend: base.earningTrend,
      heatmapBins: base.heatmapBins,
      readings: [
        AnalyticsReadingSample(
          timestamp: DateTime.utc(2026, 9, 30, 12),
          latitude: 10.123,
          longitude: 20.456,
          pressureHpa: 1000,
          synced: false,
        ),
      ],
    );
    final json = AnalyticsExportService().buildJson(handBuilt);
    expect(json, isNot(contains('10.123')));
    expect(json, contains('10.1'));
  });
}
