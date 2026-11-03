// The Collect card reports what happened, never a schedule it may not keep.
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/domain/collection_run.dart';
import 'package:wrfcoin_mobile/features/collector/domain/collection_status.dart';

final _now = DateTime(2026, 11, 2, 16);

CollectionStatus _status({
  bool isCollecting = true,
  bool serviceSupported = true,
  bool serviceRunning = true,
  CollectionServiceIssue? issue,
  DateTime? serviceRestartedAt,
  DateTime? lastReadingAt,
  String? lastRunOutcome,
  DateTime? lastRunAt,
}) => describeCollection(
  isCollecting: isCollecting,
  serviceSupported: serviceSupported,
  serviceRunning: serviceRunning,
  issue: issue,
  serviceRestartedAt: serviceRestartedAt,
  lastReadingAt: lastReadingAt,
  lastRunOutcome: lastRunOutcome,
  lastRunAt: lastRunAt,
  intervalMinutes: 15,
  now: _now,
  formatTime: (t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}',
);

void main() {
  test('off says paused', () {
    final s = _status(isCollecting: false);
    expect(s.title, 'Collection Paused');
    expect(s.isProblem, isFalse);
  });

  test('running with a recent reading gives its real time, and no promise', () {
    final s = _status(lastReadingAt: _now.subtract(const Duration(minutes: 10)));
    expect(s.title, 'Collecting with the app closed');
    expect(s.detail, 'Last reading 15:50.');
    expect(s.detail, isNot(contains('Every')));
    expect(s.isProblem, isFalse);
  });

  test('no reading yet says so', () {
    expect(_status().detail, 'No reading yet.');
  });

  test('running but silent for too long says Android may be pausing it', () {
    final s = _status(lastReadingAt: _now.subtract(const Duration(hours: 2)));
    expect(s.detail, contains('Android may be pausing'));
    expect(s.isProblem, isTrue);
  });

  for (final (outcome, words) in [
    (CollectionOutcome.barometerUnavailable, 'barometer'),
    (CollectionOutcome.batteryLow, 'battery is low'),
    (CollectionOutcome.locationTooOld, 'over a day old'),
    (CollectionOutcome.locationUnavailable, 'no location'),
    (CollectionOutcome.error, 'went wrong'),
  ]) {
    test('an empty run says why: $outcome', () {
      final s = _status(
        lastReadingAt: _now.subtract(const Duration(minutes: 20)),
        lastRunOutcome: outcome,
        lastRunAt: _now.subtract(const Duration(minutes: 5)),
      );
      expect(s.detail, contains('The try at 15:55 saved nothing'));
      expect(s.detail, contains(words));
      expect(s.isProblem, isTrue);
    });
  }

  test('a saved run is not reported as a problem', () {
    final s = _status(
      lastReadingAt: _now,
      lastRunOutcome: CollectionOutcome.readingSaved,
      lastRunAt: _now,
    );
    expect(s.isProblem, isFalse);
  });

  group('on, but the service is not running', () {
    test('no location permission', () {
      final s = _status(
        serviceRunning: false,
        issue: CollectionServiceIssue.noLocationPermission,
      );
      expect(s.title, 'Not collecting with the app closed');
      expect(s.detail, contains('needs location'));
      expect(s.isProblem, isTrue);
    });

    test('Android refused', () {
      final s = _status(
        serviceRunning: false,
        issue: CollectionServiceIssue.startRefused,
      );
      expect(s.detail, contains('would not start'));
    });

    test('unknown', () {
      expect(_status(serviceRunning: false).detail, contains('Open the app'));
    });
  });

  test('restarted on open says it had stopped, and why it may have', () {
    final s = _status(
      serviceRestartedAt: _now.subtract(const Duration(minutes: 2)),
      lastReadingAt: _now.subtract(const Duration(hours: 9)),
    );
    expect(s.detail, contains('Collection had stopped'));
    expect(s.detail, contains('phone restart'));
    expect(s.isProblem, isTrue);
  });

  test('the restart note fades after an hour', () {
    final s = _status(
      serviceRestartedAt: _now.subtract(const Duration(hours: 2)),
      lastReadingAt: _now.subtract(const Duration(minutes: 5)),
    );
    expect(s.detail, isNot(contains('Collection had stopped')));
  });

  test('a phone without the service says so', () {
    final s = _status(serviceSupported: false, serviceRunning: false);
    expect(s.title, 'Collecting while the app is open');
    expect(s.detail, contains('cannot collect with the app closed'));
  });
}
