// A collection run leaves a row whatever it ended with, an empty run never
// reports success, and each reading says where it came from.
import 'dart:io';

import 'package:dio/dio.dart';
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

  test('a job that saves a reading succeeds and tags it', () async {
    await job(runner(_Sensors()));

    final reading = (await db.getReadingHistory()).single;
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
    (
      'no barometer event',
      _Sensors(pressure: null),
      80,
      CollectionOutcome.barometerUnavailable,
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

  test('a run not yet due is an empty run too', () async {
    await job(runner(_Sensors()));
    await expectLater(
      job(runner(_Sensors())),
      throwsA(isA<CollectionRunFailed>()),
    );
    expect((await db.getReadingHistory()).length, 1);
    expect(
      (await db.getCollectionRuns()).map((r) => r.outcome),
      [CollectionOutcome.notDue, CollectionOutcome.readingSaved],
    );
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
