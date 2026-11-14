import 'collection_run.dart';

/// Why the service is not running while collection is on.
enum CollectionServiceIssue { noLocationPermission, startRefused, unknown }

class CollectionStatus {
  const CollectionStatus(this.title, this.detail, {this.isProblem = false});

  final String title;
  final String detail;

  /// The card should read as a warning.
  final bool isProblem;
}

String? emptyRunReason(String outcome) => switch (outcome) {
  CollectionOutcome.batteryLow => 'the battery is low',
  CollectionOutcome.barometerUnavailable => 'the barometer gave no data',
  CollectionOutcome.locationUnavailable => 'no location is saved yet',
  CollectionOutcome.locationTooOld => 'the saved location is over a day old',
  CollectionOutcome.error => 'something went wrong on the phone',
  CollectionOutcome.serviceStopped =>
    'the phone stopped collection in the background',
  _ => null,
};

/// What the Collect card says. It reports only what happened: never a
/// schedule the phone may not keep.
CollectionStatus describeCollection({
  required bool isCollecting,
  required bool serviceSupported,
  required bool serviceRunning,
  required CollectionServiceIssue? issue,
  required DateTime? serviceRestartedAt,
  required DateTime? lastReadingAt,
  required String? lastRunOutcome,
  required DateTime? lastRunAt,
  required int intervalMinutes,
  required DateTime now,
  required String Function(DateTime) formatTime,
}) {
  if (!isCollecting) {
    return const CollectionStatus(
      'Collection Paused',
      'Tap to start collecting',
    );
  }
  final last = lastReadingAt == null
      ? 'No reading yet.'
      : 'Last reading ${formatTime(lastReadingAt)}.';
  if (!serviceSupported) {
    return CollectionStatus(
      'Collecting while the app is open',
      '$last This phone cannot collect with the app closed.',
    );
  }
  if (!serviceRunning) {
    final why = switch (issue) {
      CollectionServiceIssue.noLocationPermission => 'WRFCoin needs location while in use. Allow it, then open the app again.',
      CollectionServiceIssue.startRefused => 'Android would not start it. Open the app again, or turn this off and on.',
      _ => 'Open the app again to restart it.',
    };
    return CollectionStatus(
      'Not collecting with the app closed',
      '$last $why',
      isProblem: true,
    );
  }

  const title = 'Collecting with the app closed';
  if (serviceRestartedAt != null &&
      now.difference(serviceRestartedAt) < const Duration(hours: 1)) {
    return CollectionStatus(
      title,
      '$last Collection had stopped, after a phone restart or to save '
      'battery. It is running again.',
      isProblem: true,
    );
  }
  final reason = lastRunOutcome == null ? null : emptyRunReason(lastRunOutcome);
  if (reason != null && lastRunAt != null) {
    return CollectionStatus(
      title,
      '$last The try at ${formatTime(lastRunAt)} saved nothing: $reason.',
      isProblem: true,
    );
  }
  final overdue = Duration(minutes: intervalMinutes * 2 + 5);
  if (lastReadingAt != null && now.difference(lastReadingAt) > overdue) {
    return CollectionStatus(
      title,
      '$last None since then: Android may be pausing collection to save '
      'battery.',
      isProblem: true,
    );
  }
  return CollectionStatus(title, last);
}
