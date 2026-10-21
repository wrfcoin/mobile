import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;

import 'package:drift/native.dart';
// Test-only: background failures carry their original SQLite cause.
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';
import 'package:wrfcoin_mobile/services/storage/db_path.dart';

Future<void> insertOld(AppDatabase db) => db.insertReading(
  SensorReadingsCompanion.insert(
    latitude: 1,
    longitude: 2,
    pressureHpa: 1000,
    timestamp: DateTime.utc(2026, 9, 29),
  ),
);
final _cutoff = DateTime.utc(2026, 9, 30);

class _StaleAckDb extends AppDatabase {
  _StaleAckDb() : super(NativeDatabase.memory());
  bool stale = false;
  @override
  Future<SyncMetadataEntry?> getSyncMetadata(String syncTableName) async {
    final stored = await super.getSyncMetadata(syncTableName);
    return stale && syncTableName == staleReadingsNoticeTableName
        ? stored?.copyWith(pendingCount: 100)
        : stored;
  }
}

class _AdmissionObserver extends QueryInterceptor {
  var requested = Completer<void>();

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) {
    if (executor is TransactionExecutor && !requested.isCompleted) {
      requested.complete();
    }
    return super.ensureOpen(executor, user);
  }
}

void main() {
  test(
    'acknowledge subtracts from storage rather than a stale client count',
    () async {
      final db = _StaleAckDb();
      addTearDown(db.close);
      await db.upsertSyncMetadata(
        syncTableName: staleReadingsNoticeTableName,
        pendingCount: 5,
      );
      db.stale = true;
      await db.acknowledgeStaleReadings(3);
      expect(
        (await db.select(db.syncMetadataEntries).get()).single.pendingCount,
        2,
      );
      await db.acknowledgeStaleReadings(3);
      expect(await db.select(db.syncMetadataEntries).get(), isEmpty);
    },
  );

  test(
    'nonpositive acknowledgement cannot add to or delete a notice',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.upsertSyncMetadata(
        syncTableName: staleReadingsNoticeTableName,
        pendingCount: 5,
      );
      await db.acknowledgeStaleReadings(0);
      await db.acknowledgeStaleReadings(-2);
      expect(
        (await db.getSyncMetadata(staleReadingsNoticeTableName))?.pendingCount,
        5,
      );
    },
  );

  test('native writer admission waits for a held transaction without replaying work', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sol-k-held-writer-',
    );
    final file = File('${directory.path}/notices.sqlite');
    final observer = _AdmissionObserver();
    final a = AppDatabase(openNativeAppDatabase(file));
    final b = AppDatabase(openNativeAppDatabase(file).interceptWith(observer));
    final release = Completer<void>();
    final held = Completer<void>();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await a.close();
      await b.close();
      await directory.delete(recursive: true);
    });
    await insertOld(a);
    await b.getPendingSyncCount();
    observer.requested = Completer<void>();
    final holder = a.transaction(() async {
      await a.customStatement('UPDATE sensor_readings SET pressure_hpa = 1001');
      held.complete();
      await release.future;
    });
    await held.future;
    final writer = b.dropStaleReadingsWithNotice(_cutoff);
    final result = expectLater(writer, completion(1));
    await observer.requested.future.timeout(const Duration(seconds: 10));
    // Deliberately exceed the old 20 ms fixture budget while a real competing
    // transaction owns the lock. Elapsed time never signals operation success.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    release.complete();
    await holder;
    await result;
    expect(await a.getPendingSyncCount(), 0);
    expect(
      (await a.getSyncMetadata(staleReadingsNoticeTableName))?.pendingCount,
      1,
    );
  });

  test('a lock held past admission deadline fails without dropping or counting data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sol-k-lock-deadline-',
    );
    final file = File('${directory.path}/notices.sqlite');
    final a = AppDatabase(openNativeAppDatabase(file));
    final b = AppDatabase(openNativeAppDatabase(file));
    final release = Completer<void>();
    final held = Completer<void>();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await a.close();
      await b.close();
      await directory.delete(recursive: true);
    });
    await insertOld(a);
    await b.getPendingSyncCount();
    final holder = a.transaction(() async {
      await a.customStatement('UPDATE sensor_readings SET pressure_hpa = 1001');
      held.complete();
      await release.future;
    });
    await held.future;
    final clock = Stopwatch()..start();
    await expectLater(
      b
          .dropStaleReadingsWithNotice(_cutoff)
          .timeout(const Duration(seconds: 15)),
      throwsA(
        predicate<Object>((error) {
          final cause = error is DriftRemoteException
              ? error.remoteCause
              : error;
          return cause is SqliteException && (cause.resultCode & 0xff) == 5;
        }),
      ),
    );
    // A failure time budget must measure elapsed time, not assumed sleep time.
    expect(clock.elapsed, greaterThanOrEqualTo(const Duration(seconds: 5)));
    release.complete();
    await holder;
    expect(await b.getPendingSyncCount(), 1);
    expect(await b.getSyncMetadata(staleReadingsNoticeTableName), isNull);
  });

  test('two background connections commit 51 drops and retain count during concurrent acknowledgement', () async {
    final directory = await Directory.systemTemp.createTemp('sol-b14-notice-');
    final file = File('${directory.path}/notices.sqlite');
    final a = AppDatabase(openNativeAppDatabase(file));
    final b = AppDatabase(openNativeAppDatabase(file));
    addTearDown(() async {
      await a.close();
      await b.close();
      await directory.delete(recursive: true);
    });
    // Initialize before opening the second connection, avoiding schema races.
    await insertOld(a);
    await b.getPendingSyncCount();
    Future<int> drops(AppDatabase db, int cycles) async {
      var committed = 0;
      for (var i = 0; i < cycles; i++) {
        await insertOld(db);
        committed += await db.dropStaleReadingsWithNotice(_cutoff);
      }
      return committed;
    }

    final committed = await Future.wait([drops(a, 25), drops(b, 25)]);
    expect(committed.reduce((x, y) => x + y), 51);
    expect(await a.getPendingSyncCount(), 0);
    final rows = await a.select(a.syncMetadataEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.pendingCount, 51);
    Future<void> acknowledge() async {
      for (var i = 0; i < 10; i++) {
        await b.acknowledgeStaleReadings(1);
      }
    }

    final phase = await Future.wait<Object?>([drops(a, 10), acknowledge()]);
    expect(phase.first, 10);
    expect(
      (await a.getSyncMetadata(staleReadingsNoticeTableName))?.pendingCount,
      51,
    );
    expect(await a.getPendingSyncCount(), 0);
  });
}
