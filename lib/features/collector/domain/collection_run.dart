/// Where a saved reading came from. Stored on each reading, so later evidence
/// needs no guesswork. A null source in the database means the reading is
/// older than this column.
enum ReadingSource {
  /// The user tapped Collect Now.
  collectNow('collect_now'),

  /// Taken automatically because the app was opened.
  appOpen('app_open'),

  /// Taken by the foreground collection service, app closed or not.
  service('service'),

  /// Taken by the periodic WorkManager job.
  job('job');

  const ReadingSource(this.dbValue);
  final String dbValue;

  static ReadingSource? fromDb(String? value) {
    for (final source in values) {
      if (source.dbValue == value) return source;
    }
    return null;
  }
}

/// Which background or foreground step a [CollectionRun] row describes:
/// a [ReadingSource] value, or one of these for an upload.
abstract final class CollectionRunKind {
  static const syncJob = 'sync_job';
  static const syncService = 'sync_service';
}

/// What a collection run ended with. Only [readingSaved] means a reading
/// exists; every other value is an empty run.
abstract final class CollectionOutcome {
  static const readingSaved = 'reading_saved';
  static const batteryLow = 'battery_low';
  static const barometerUnavailable = 'barometer_unavailable';
  static const locationUnavailable = 'location_unavailable';
  static const notDue = 'not_due';
  static const error = 'error';
}

/// Thrown out of a WorkManager task that did not do its job. WorkManager then
/// records a failure instead of a success. (A plain `false` would ask it to
/// retry with backoff, which delays the next periodic run.)
class CollectionRunFailed implements Exception {
  const CollectionRunFailed(this.outcome);
  final String outcome;

  @override
  String toString() => 'CollectionRunFailed($outcome)';
}
