// Schema v3 -> v4: stored reading and pending-image coordinates are rewritten to the 0.1 degree grid.
// Opens a REAL pre-change database file (user_version 3, 3-decimal coordinates). Synthetic positions.
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

void _createV3File(String path) {
  final raw = sql.sqlite3.open(path);
  raw.execute('''
    CREATE TABLE sensor_readings (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      latitude REAL NOT NULL, longitude REAL NOT NULL, pressure_hpa REAL NOT NULL,
      timestamp INTEGER NOT NULL, synced INTEGER NOT NULL DEFAULT 0 CHECK (synced IN (0, 1)));
    CREATE TABLE pending_images (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      file_path TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL,
      image_metadata TEXT NOT NULL DEFAULT '{}', timestamp INTEGER NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0 CHECK (synced IN (0, 1)));
    CREATE TABLE sync_metadata_entries (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      sync_table_name TEXT NOT NULL, last_sync_at INTEGER NULL, last_sync_attempt_at INTEGER NULL,
      last_sync_error TEXT NULL, pending_count INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE offline_data_entries (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, cached_at INTEGER NOT NULL);
  ''');
  raw.execute('INSERT INTO sensor_readings (id, latitude, longitude, pressure_hpa, timestamp, synced) VALUES '
      '(5, 10.123, 20.456, 1013.25, 1790000000, 0),'
      '(6, -10.04, -20.05, 1001.5, 1790000100, 1),' // synced history, ties and negatives
      '(7, -0.04, 0.04, 999.0, 1790000200, 0),' // would round to -0.0
      '(8, 89.96, -179.96, 1000.0, 1790000300, 1)');
  raw.execute("INSERT INTO pending_images (id, file_path, latitude, longitude, image_metadata, timestamp, synced) VALUES "
      "(3, '/tmp/x.jpg', 10.123, 20.456, '{\"k\":1}', 1790000400, 0)");
  raw.execute('PRAGMA user_version = 3');
  raw.close();
}

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('coord_migration_');
    path = '${dir.path}/app.sqlite';
    _createV3File(path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('reopening a v3 file rewrites stored coordinates to 0.1, keeping ids, time, sync and pressure', () async {
    final db = AppDatabase(NativeDatabase(File(path)));
    addTearDown(db.close);
    final rows = await (db.select(db.sensorReadings)..orderBy([(r) => OrderingTerm.asc(r.id)])).get();
    expect(rows.map((r) => r.id), [5, 6, 7, 8]);
    expect(rows[0].latitude, 10.1);
    expect(rows[0].longitude, 20.5);
    expect(rows[1].latitude, -10.0);
    expect(rows[1].longitude, -20.1); // -20.05 rounds half away from zero
    expect(rows[2].latitude.toString(), '0.0'); // never -0.0
    expect(rows[2].longitude, 0.0);
    expect(rows[3].latitude, 90.0);
    expect(rows[3].longitude, -180.0);
    // everything else is preserved, including the already-synced history
    expect(rows.map((r) => r.synced), [false, true, false, true]);
    expect(rows.map((r) => r.pressureHpa), [1013.25, 1001.5, 999.0, 1000.0]);
    expect(rows[1].timestamp.millisecondsSinceEpoch ~/ 1000, 1790000100);
    final images = await db.select(db.pendingImages).get();
    expect(images.single.id, 3);
    expect(images.single.latitude, 10.1);
    expect(images.single.longitude, 20.5);
    expect(images.single.filePath, '/tmp/x.jpg');
    expect(images.single.imageMetadata, '{"k":1}');
  });

  test('the stored COLUMNS are coarse (inspected with a second connection, not through the model)', () async {
    final db = AppDatabase(NativeDatabase(File(path)));
    await db.getPendingSyncCount(); // forces open + migration
    await db.close();
    final raw = sql.sqlite3.open(path);
    final values = raw.select('SELECT latitude, longitude FROM sensor_readings UNION ALL SELECT latitude, longitude FROM pending_images');
    for (final row in values) {
      for (final v in [row['latitude'] as double, row['longitude'] as double]) {
        expect((v * 10).roundToDouble() / 10, v, reason: 'stored $v is not on the 0.1 grid');
      }
    }
    expect(raw.select('PRAGMA user_version').single.values.single, 4);
    raw.close();
  });

  test('a second open changes nothing (idempotent) and a fresh database is at v4', () async {
    final first = AppDatabase(NativeDatabase(File(path)));
    final before = await first.select(first.sensorReadings).get();
    await first.close();
    final second = AppDatabase(NativeDatabase(File(path)));
    addTearDown(second.close);
    final after = await second.select(second.sensorReadings).get();
    expect(after.map((r) => [r.id, r.latitude, r.longitude]), before.map((r) => [r.id, r.latitude, r.longitude]));
    expect(second.schemaVersion, 4);
  });
}
