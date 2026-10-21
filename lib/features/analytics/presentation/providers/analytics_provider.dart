import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../collector/data/repositories/collector_repository_impl.dart';
import '../../../collector/data/services/collector_preferences.dart';
import '../../../collector/presentation/providers/collector_provider.dart';
import '../../data/analytics_calculations.dart';
import '../../data/analytics_models.dart';
import '../../../../services/storage/local_db.dart';
import '../../../weather/domain/models/coarse_location.dart';

/// A stored reading as an analytics sample, with the position on the 0.1 degree grid (rows stored
/// before that ruling may still carry 3 decimals).
AnalyticsReadingSample analyticsSampleFromRow(SensorReading row) =>
    AnalyticsReadingSample(
      timestamp: row.timestamp,
      latitude: CoarseLocation.coarsen(row.latitude),
      longitude: CoarseLocation.coarsen(row.longitude),
      pressureHpa: row.pressureHpa,
      synced: row.synced,
    );

final analyticsSnapshotProvider = FutureProvider<AnalyticsSnapshot>((
  ref,
) async {
  final collectorState = ref.watch(collectorProvider);
  final validationEvents = await ref
      .watch(collectorPreferencesProvider)
      .loadValidationEvents();

  final readings = <AnalyticsReadingSample>[];
  if (!kIsWeb) {
    final db = ref.watch(appDatabaseProvider);
    final rows = await db.select(db.sensorReadings).get();
    readings.addAll(rows.map(analyticsSampleFromRow).toList(growable: false));
  }

  return buildAnalyticsSnapshot(
    readings: readings,
    validationEvents: validationEvents,
    syncedSubmissionCount: collectorState.syncedSubmissionCount,
    earnedRewardWrf: collectorState.earnedRewardWrf,
    rewardTotalsAvailable: collectorState.rewardTotalsAvailable,
  );
});
