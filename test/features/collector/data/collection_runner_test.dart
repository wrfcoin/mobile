// A collection run leaves a row whatever it ended with, an empty run never
// reports success, and each reading says where it came from.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collection_runner.dart';
import 'package:wrfcoin_mobile/features/collector/domain/collection_run.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/background/sensor_worker.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fakes.dart';

class _Sensors extends SensorDataSource {
  _Sensors({this.location = (lat: 46.8, lng: -92.1), this.pressure = 1013.0})
    : super(LocationService());
  final ({double lat, double lng})? location;
  final double? pressure;
  @override
  Future<({double lat, double lng})?> readLocation() async => location;
  @override
  Future<({double lat, double lng})?> readLocationQuietly() async => location;
  @override
  Future<double?> readBarometer() async => pressure;
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  CollectionRunner runner(_Sensors sensors, {int battery = 80}) =>
      CollectionRunner(
        CollectorRepository(
          sensorDataSource: sensors,
          batteryMonitor: FakeBatteryMonitor(batteryLevel: battery),
          apiClient: ApiClient(dio: Dio()),
          db: db,
        ),
      );

  Future<void> job(CollectionRunner r) =>
      runCollectionJob(r, batteryThreshold: 15, baseIntervalMinutes: 15);

  /// A reading from when the app last read location.
  Future<void> seedFresh(Duration ago) {
    final at = DateTime.now().subtract(ago);
    return db.insertReading(
      SensorReadingsCompanion.insert(
        latitude: 46.8,
        longitude: -92.1,
        pressureHpa: 1012,
        timestamp: at,
        source: const Value('collect_now'),
        locationSource: const Value(LocationSource.fresh),
        locationAt: Value(at),
      ),
    );
  }

  test('a job that saves a reading succeeds and tags it', () async {
    await seedFresh(const Duration(hours: 1));
    await job(runner(_Sensors()));

    final reading = (await db.getReadingHistory()).last;
    expect(reading.source, 'job');
    final run = (await db.getCollectionRuns()).single;
    expect(run.kind, 'job');
    expect(run.outcome, CollectionOutcome.readingSaved);
  });

  for (final (name, sensors, battery, outcome) in [
    (
      'no location',
      _Sensors(location: null),
      80,
      CollectionOutcome.locationUnavailable,
    ),

    ('low battery', _Sensors(), 5, CollectionOutcome.batteryLow),
  ]) {
    test('$name: no reading, a saved reason, and not a success', () async {
      await expectLater(
        job(runner(sensors, battery: battery)),
        throwsA(
          isA<CollectionRunFailed>().having((e) => e.outcome, 'outcome', outcome),
        ),
      );
      expect(await db.getReadingHistory(), isEmpty);
      expect(await db.getPendingSyncCount(), 0);
      expect((await db.getCollectionRuns()).single.outcome, outcome);
    });
  }

  test('no barometer event: no reading, and not a success', () async {
    await seedFresh(const Duration(hours: 1));
    await expectLater(
      job(runner(_Sensors(pressure: null))),
      throwsA(isA<CollectionRunFailed>()),
    );
    expect((await db.getReadingHistory()).length, 1);
    expect(
      (await db.getCollectionRuns()).single.outcome,
      CollectionOutcome.barometerUnavailable,
    );
  });

  test('a run not yet due is an empty run too', () async {
    await seedFresh(const Duration(minutes: 5));
    await expectLater(
      job(runner(_Sensors())),
      throwsA(isA<CollectionRunFailed>()),
    );
    expect((await db.getReadingHistory()).length, 1);
    expect(
      (await db.getCollectionRuns()).single.outcome,
      CollectionOutcome.notDue,
    );
  });

  group('rough location', () {
    test('the job never reads location, and labels the reused cell', () async {
      await seedFresh(const Duration(hours: 3));
      final original = (await db.getReadingHistory()).single.locationAt;
      await runner(_Sensors(location: (lat: 1.0, lng: 2.0))).collect(
        source: ReadingSource.job,
      );

      final reading = (await db.getReadingHistory()).last;
      expect(reading.latitude, 46.8);
      expect(reading.longitude, -92.1);
      expect(reading.locationSource, LocationSource.reused);
      expect(reading.locationAt, original);
    });

    test('the service prefers a quiet fresh read, rounded to the grid', () async {
      await seedFresh(const Duration(hours: 3));
      await runner(_Sensors(location: (lat: 47.04, lng: -92.26))).collect(
        source: ReadingSource.service,
      );

      final reading = (await db.getReadingHistory()).last;
      expect(reading.latitude, 47.0);
      expect(reading.longitude, -92.3);
      expect(reading.locationSource, LocationSource.fresh);
    });

    test('the service reuses the cell when no fix comes', () async {
      await seedFresh(const Duration(hours: 3));
      await runner(_Sensors(location: null)).collect(
        source: ReadingSource.service,
      );
      expect(
        (await db.getReadingHistory()).last.locationSource,
        LocationSource.reused,
      );
    });

    test('reuse does not reset the cell age', () async {
      await seedFresh(const Duration(hours: 23));
      await runner(_Sensors(location: null)).collect(
        source: ReadingSource.service,
      );
      await db.customStatement(
        'UPDATE sensor_readings SET location_at = location_at - 7200',
      );
      final result = await runner(_Sensors(location: null)).collect(
        source: ReadingSource.service,
      );
      expect(result.failureReason, CollectReadingFailureReason.locationTooOld);
    });

    test('a cell over a day old is refused with its own reason', () async {
      await seedFresh(const Duration(hours: 25));
      final result = await runner(_Sensors(location: null)).collect(
        source: ReadingSource.service,
      );
      expect(result.failureReason, CollectReadingFailureReason.locationTooOld);
      expect((await db.getReadingHistory()).length, 1);
      expect(
        (await db.getCollectionRuns()).single.outcome,
        CollectionOutcome.locationTooOld,
      );
    });

    test('Collect Now still needs a real read, and never reuses', () async {
      await seedFresh(const Duration(hours: 1));
      final result = await runner(_Sensors(location: null)).collect(
        source: ReadingSource.collectNow,
        force: true,
      );
      expect(
        result.failureReason,
        CollectReadingFailureReason.locationUnavailable,
      );
    });

    test('an app-open reading never reuses a cell', () async {
      await seedFresh(const Duration(hours: 1));
      final result = await runner(_Sensors(location: null)).collect(
        source: ReadingSource.appOpen,
      );
      expect(
        result.failureReason,
        CollectReadingFailureReason.locationUnavailable,
      );
    });

    test('a row from before this was recorded is never reused', () async {
      await db.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 10,
          longitude: 20,
          pressureHpa: 1000,
          timestamp: DateTime.now(),
        ),
      );
      final result = await runner(_Sensors(location: null)).collect(
        source: ReadingSource.job,
      );
      expect(
        result.failureReason,
        CollectReadingFailureReason.locationUnavailable,
      );
    });
  });

  test('Collect Now readings say so', () async {
    await runner(_Sensors()).collect(
      source: ReadingSource.collectNow,
      force: true,
    );
    expect((await db.getReadingHistory()).single.source, 'collect_now');
  });

  group('upload runs', () {
    SyncRunResult result(SyncRunReason reason, {int accepted = 0}) =>
        SyncRunResult(
          acceptedCount: accepted,
          failedCount: 0,
          pendingCount: 0,
          reason: reason,
        );

    test('uploaded and idle succeed, and are saved', () async {
      await runSyncJob(
        () async => result(SyncRunReason.success, accepted: 2),
        db,
        kind: CollectionRunKind.syncJob,
      );
      await runSyncJob(
        () async => result(SyncRunReason.idle),
        db,
        kind: CollectionRunKind.syncJob,
      );
      final runs = await db.getCollectionRuns();
      expect(runs.map((r) => r.outcome).toSet(), {'success', 'idle'});
      expect(runs.map((r) => r.acceptedCount).toSet(), {2, 0});
    });

    for (final reason in [
      SyncRunReason.offline,
      SyncRunReason.rejected,
      SyncRunReason.activationUnknown,
      SyncRunReason.awaitingForeground,
    ]) {
      test('${reason.name} is saved and is not a success', () async {
        await expectLater(
          runSyncJob(
            () async => result(reason),
            db,
            kind: CollectionRunKind.syncJob,
          ),
          throwsA(isA<CollectionRunFailed>()),
        );
        expect((await db.getCollectionRuns()).single.outcome, reason.name);
      });
    }

    test('a crash is saved with its type only', () async {
      await expectLater(
        runSyncJob(
          () async => throw StateError('secret detail'),
          db,
          kind: CollectionRunKind.syncJob,
        ),
        throwsStateError,
      );
      final run = (await db.getCollectionRuns()).single;
      expect(run.outcome, CollectionOutcome.error);
      expect(run.detail, 'StateError');
    });
  });

  test('old runs are pruned', () async {
    final at = DateTime.utc(2026, 11, 2);
    for (var i = 0; i < AppDatabase.maxCollectionRuns + 3; i++) {
      await db.recordCollectionRun(
        kind: 'job',
        outcome: 'x',
        startedAt: at,
        finishedAt: at,
      );
    }
    final rows = await db
        .customSelect('SELECT COUNT(*) AS c FROM collection_runs')
        .getSingle();
    expect(rows.read<int>('c'), AppDatabase.maxCollectionRuns);
  });

  test('a v4 database gains the new columns and keeps its readings', () async {
    final dir = Directory.systemTemp.createTempSync('runs_migration_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.sqlite';
    final raw = sql.sqlite3.open(path);
    raw.execute('''
      CREATE TABLE sensor_readings (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL, longitude REAL NOT NULL, pressure_hpa REAL NOT NULL,
        timestamp INTEGER NOT NULL, synced INTEGER NOT NULL DEFAULT 0 CHECK (synced IN (0, 1)));
      INSERT INTO sensor_readings (id, latitude, longitude, pressure_hpa, timestamp, synced)
        VALUES (9, 46.8, -92.1, 1013.25, 1790000000, 1);
      PRAGMA user_version = 4;
    ''');
    raw.close();

    final migrated = AppDatabase(NativeDatabase(File(path)));
    addTearDown(migrated.close);
    final reading = (await migrated.getReadingHistory()).single;
    expect(reading.id, 9);
    expect(reading.source, isNull);
    expect(reading.locationSource, isNull);
    expect(reading.locationAt, isNull);
    expect(await migrated.getCollectionRuns(), isEmpty);
  });
}
