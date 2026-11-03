// The Collect toggle starts and stops the service, and opening the app takes
// a deliberate reading only when one is due.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/domain/collection_run.dart';
import 'package:wrfcoin_mobile/features/collector/domain/collection_status.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/services/background/collection_service.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fakes.dart';

class _Service extends CollectionServiceController {
  CollectionServiceStart startResult = CollectionServiceStart.started;
  bool running = false;
  int starts = 0;
  int stops = 0;
  int? interval;
  void Function()? stopped;

  @override
  Future<bool> get isRunning async => running;
  @override
  Future<void> requestNotificationPermission() async {}
  @override
  Future<CollectionServiceStart> start({required int intervalMinutes}) async {
    starts++;
    running = startResult == CollectionServiceStart.started;
    return startResult;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  @override
  Future<void> setInterval(int intervalMinutes) async {
    interval = intervalMinutes;
  }

  @override
  void Function() listen(
    void Function() onStopped, {
    void Function()? onTick,
  }) {
    stopped = onStopped;
    return () {};
  }
}

class _Location extends LocationService {
  bool granted = true;
  int requests = 0;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<LocationPermission> checkPermission() async =>
      granted ? LocationPermission.whileInUse : LocationPermission.denied;
}

class _Repo extends FakeCollectorRepository {
  _Repo()
    : super(
        reading: SensorReadingModel(
          latitude: 1,
          longitude: 2,
          pressureHpa: 1000,
          timestamp: DateTime.utc(2026, 11, 2),
        ),
      );
  final calls = <(ReadingSource, bool)>[];
  @override
  Future<CollectReadingResult> collectReading({
    int batteryThreshold = 15,
    int baseIntervalMinutes = 15,
    bool force = false,
    ReadingSource source = ReadingSource.collectNow,
    Duration dueGrace = Duration.zero,
  }) {
    calls.add((source, force));
    return super.collectReading(
      batteryThreshold: batteryThreshold,
      baseIntervalMinutes: baseIntervalMinutes,
      force: force,
      source: source,
    );
  }
}

class _ConsentStore extends AppPreferencesStore {
  const _ConsentStore(this.consent);
  final bool consent;
  @override
  Future<AppPreferences> load() async => AppPreferences(
    consent: ConsentSettings(
      sensorCollection: consent,
      preciseLocation: consent,
    ),
  );
}

CollectionRun _run(String outcome) => CollectionRun(
  id: 1,
  kind: ReadingSource.service.dbValue,
  outcome: outcome,
  acceptedCount: 0,
  startedAt: DateTime.utc(2026, 11, 2),
  finishedAt: DateTime.utc(2026, 11, 2),
);

void main() {
  late _Service service;
  late _Location location;
  late _Repo repo;
  late ProviderContainer container;

  Future<CollectorNotifier> build({
    bool collecting = false,
    bool consent = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'collector.isCollecting': collecting,
    });
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        collectorRepositoryProvider.overrideWithValue(repo),
        syncWorkerProvider.overrideWithValue(FakeSyncWorker()),
        collectorPreferencesProvider.overrideWithValue(
          const CollectorPreferences(),
        ),
        appPreferencesStoreProvider.overrideWithValue(_ConsentStore(consent)),
        appLoggerProvider.overrideWithValue(
          const AppLogger(sinks: <LogSink>[], verbose: false),
        ),
        collectionServiceProvider.overrideWithValue(service),
        locationServiceProvider.overrideWithValue(location),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(collectorProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return notifier;
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    service = _Service();
    location = _Location();
    repo = _Repo();
  });

  group('the toggle', () {
    test('on: starts the service and saves it', () async {
      final notifier = await build();
      await notifier.startCollecting();
      expect(service.starts, 1);
      expect(notifier.state.isCollecting, isTrue);
      expect(await const CollectorPreferences().isCollectingNow(), isTrue);
    });

    test('location refused: stays off and says why', () async {
      location.granted = false;
      final notifier = await build();
      await notifier.startCollecting();
      expect(service.starts, 0);
      expect(notifier.state.isCollecting, isFalse);
      expect(notifier.state.syncMessage, contains('location'));
    });

    test('Android refuses the service: stays off and says so', () async {
      service.startResult = CollectionServiceStart.failed;
      final notifier = await build();
      await notifier.startCollecting();
      expect(notifier.state.isCollecting, isFalse);
      expect(notifier.state.syncMessage, contains('would not start'));
      expect(await const CollectorPreferences().isCollectingNow(), isFalse);
    });

    test('no consent: nothing starts', () async {
      final notifier = await build(consent: false);
      await notifier.startCollecting();
      expect(service.starts, 0);
      expect(location.requests, 0);
    });

    test('off: stops the service and saves it', () async {
      final notifier = await build(collecting: true);
      await notifier.stopCollecting();
      expect(service.stops, 1);
      expect(notifier.state.isCollecting, isFalse);
      expect(await const CollectorPreferences().isCollectingNow(), isFalse);
    });

    test('revoking consent stops the service', () async {
      final notifier = await build(collecting: true);
      await notifier.handleConsentRevoked();
      expect(service.stops, 1);
    });

    test('a new interval reaches a running service', () async {
      final notifier = await build(collecting: true);
      await notifier.setInterval(30);
      expect(service.interval, 30);
    });
  });

  group('the notification Stop button', () {
    test('while the app is open, the toggle goes off', () async {
      final notifier = await build(collecting: true);
      service.stopped!();
      expect(notifier.state.isCollecting, isFalse);
    });

    test('while the app was asleep, opening it shows off and restarts '
        'nothing', () async {
      final notifier = await build(collecting: true);
      final starts = service.starts;
      service.running = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('collector.isCollecting', false);
      await notifier.handleAppResume();
      expect(notifier.state.isCollecting, isFalse);
      expect(service.starts, starts);
    });
  });

  group('what the card is told', () {
    test('a restarted service is reported as having stopped', () async {
      final notifier = await build(collecting: true);
      expect(notifier.state.serviceRunning, isTrue);
      expect(notifier.state.serviceRestartedAt, isNotNull);
    });

    test('a running service is not', () async {
      service.running = true;
      final notifier = await build(collecting: true);
      expect(notifier.state.serviceRunning, isTrue);
      expect(notifier.state.serviceRestartedAt, isNull);
    });

    test('Android refusing a restart is reported', () async {
      service.startResult = CollectionServiceStart.failed;
      final notifier = await build(collecting: true);
      expect(notifier.state.serviceRunning, isFalse);
      expect(notifier.state.serviceIssue, CollectionServiceIssue.startRefused);
    });

    test('revoked location is reported', () async {
      location.granted = false;
      final notifier = await build(collecting: true);
      expect(
        notifier.state.serviceIssue,
        CollectionServiceIssue.noLocationPermission,
      );
    });

    test('a not-due run is not the last thing to report', () async {
      final store = repo.db as FakeCollectorLocalStore;
      store.collectionRuns = [_run(CollectionOutcome.notDue), _run('x')];
      final notifier = await build();
      expect(notifier.state.lastRunOutcome, 'x');
    });

    test('a turned-on toggle clears an old restart note', () async {
      final notifier = await build(collecting: true);
      await notifier.stopCollecting();
      expect(notifier.state.serviceRestartedAt, isNull);
      await notifier.startCollecting();
      expect(notifier.state.serviceRestartedAt, isNull);
      expect(notifier.state.isCollecting, isTrue);
    });
  });

  group('opening the app', () {
    test('collection on: restarts a stopped service, no dialogs, and takes '
        'one non-forced app-open reading', () async {
      await build(collecting: true);
      expect(service.starts, 1);
      expect(location.requests, 0);
      expect(repo.calls, [(ReadingSource.appOpen, false)]);
    });

    test('a running service is left alone', () async {
      service.running = true;
      await build(collecting: true);
      expect(service.starts, 0);
    });

    test('location revoked: no service, and no dialog', () async {
      location.granted = false;
      await build(collecting: true);
      expect(service.starts, 0);
      expect(location.requests, 0);
    });

    test('collection off: no reading and no service', () async {
      await build();
      expect(repo.calls, isEmpty);
      expect(service.starts, 0);
    });

    test('no consent: no reading and no service', () async {
      await build(collecting: true, consent: false);
      expect(repo.calls, isEmpty);
      expect(service.starts, 0);
    });

    test('returning to the app checks again', () async {
      final notifier = await build(collecting: true);
      service.running = false;
      await notifier.handleAppResume();
      expect(service.starts, 2);
      expect(repo.calls.length, 2);
      expect(repo.calls.every((c) => c.$1 == ReadingSource.appOpen), isTrue);
    });
  });

  test('Collect Now is forced and says it was Collect Now', () async {
    final notifier = await build();
    await notifier.collectNow();
    expect(repo.calls, [(ReadingSource.collectNow, true)]);
  });
}
