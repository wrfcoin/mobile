import '../../../../services/background/sync_worker.dart';
import '../../domain/collection_run.dart';
import '../repositories/collector_repository_impl.dart';

/// Takes one reading and saves what happened, whatever happened.
class CollectionRunner {
  CollectionRunner(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final CollectorRepository _repository;
  final DateTime Function() _now;

  Future<CollectReadingResult> collect({
    required ReadingSource source,
    int batteryThreshold = 15,
    int baseIntervalMinutes = 15,
    bool force = false,
  }) async {
    final startedAt = _now();
    try {
      final result = await _repository.collectReading(
        batteryThreshold: batteryThreshold,
        baseIntervalMinutes: baseIntervalMinutes,
        force: force,
        source: source,
      );
      await _repository.db.recordCollectionRun(
        kind: source.dbValue,
        outcome: outcomeOf(result),
        startedAt: startedAt,
        finishedAt: _now(),
      );
      return result;
    } catch (error) {
      await _repository.db.recordCollectionRun(
        kind: source.dbValue,
        outcome: CollectionOutcome.error,
        detail: error.runtimeType.toString(),
        startedAt: startedAt,
        finishedAt: _now(),
      );
      rethrow;
    }
  }

  static String outcomeOf(CollectReadingResult result) {
    if (result.isSuccess) return CollectionOutcome.readingSaved;
    return switch (result.failureReason) {
      CollectReadingFailureReason.batteryLow => CollectionOutcome.batteryLow,
      CollectReadingFailureReason.barometerUnavailable =>
        CollectionOutcome.barometerUnavailable,
      CollectReadingFailureReason.locationUnavailable =>
        CollectionOutcome.locationUnavailable,
      CollectReadingFailureReason.locationTooOld =>
        CollectionOutcome.locationTooOld,
      CollectReadingFailureReason.stationaryBackoff => CollectionOutcome.notDue,
      null => CollectionOutcome.error,
    };
  }
}

/// Whether an upload run did its job. Nothing to upload is fine; anything
/// that left readings behind for a reason is not.
bool syncRunSucceeded(SyncRunReason reason) =>
    reason == SyncRunReason.success || reason == SyncRunReason.idle;
