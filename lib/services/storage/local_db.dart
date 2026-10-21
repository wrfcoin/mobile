import 'package:drift/drift.dart';

import '../../features/collector/data/repositories/collector_repository_impl.dart';

part 'local_db.g.dart';

const staleReadingsNoticeTableName = 'sensor_readings_stale_notice';

/// Generic key/value offline cache table.
/// `cacheKey` is unique per (feature, resource) — callers choose a namespaced
/// key like `weather:forecast:local` so rows are unambiguous.
class OfflineDataEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cacheKey => text().unique()();
  TextColumn get payload => text()(); // JSON-encoded value
  DateTimeColumn get cachedAt => dateTime()();
}

class SensorReadings extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get pressureHpa => real()();
  DateTimeColumn get timestamp => dateTime()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

class PendingImages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get imageMetadata => text().withDefault(const Constant('{}'))();
  DateTimeColumn get timestamp => dateTime()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

class SyncMetadataEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncTableName => text()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  DateTimeColumn get lastSyncAttemptAt => dateTime().nullable()();
  TextColumn get lastSyncError => text().nullable()();
  IntColumn get pendingCount => integer().withDefault(const Constant(0))();
}

@DriftDatabase(
  tables: [
    SensorReadings,
    PendingImages,
    SyncMetadataEntries,
    OfflineDataEntries,
  ],
)
class AppDatabase extends _$AppDatabase implements CollectorLocalStore {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(
          syncMetadataEntries,
          syncMetadataEntries.lastSyncAttemptAt,
        );
        await m.addColumn(
          syncMetadataEntries,
          syncMetadataEntries.lastSyncError,
        );
      }
      if (from < 3) {
        await m.createTable(offlineDataEntries);
      }
      if (from < 4) {
        // Owner ruling 2026-09-30: reading locations are kept at 0.1 degree only. Rewrite what was
        // stored at 3 decimals, including already-synced history and pending-image rows, in this
        // migration's transaction. SQLite round() rounds half away from zero like Dart's
        // roundToDouble; `+ 0.0` turns -0.0 into 0.0. Ids, timestamps, sync state and pressure
        // are not touched.
        for (final table in const ['sensor_readings', 'pending_images']) {
          await customStatement(
            'UPDATE $table SET '
            'latitude = round(latitude * 10) / 10.0 + 0.0, '
            'longitude = round(longitude * 10) / 10.0 + 0.0',
          );
        }
      }
    },
  );

  @override
  Future<int> insertReading(SensorReadingsCompanion reading) =>
      into(sensorReadings).insert(reading);

  @override
  Future<SensorReading?> getLatestReading() {
    return (select(sensorReadings)
          ..orderBy([
            (row) => OrderingTerm(
              expression: row.timestamp,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<List<SensorReading>> getReadingHistory({int limit = 5000}) {
    return (select(sensorReadings)
          ..orderBy([
            (row) =>
                OrderingTerm(expression: row.timestamp, mode: OrderingMode.asc),
          ])
          ..limit(limit))
        .get();
  }

  /// Oldest first: core4 rejects a reading older than the station's previous
  /// accepted one (`weather/validation.rs:649-690`), so order matters.
  Future<List<SensorReading>> getUnsyncedReadings({int limit = 50}) =>
      (select(sensorReadings)
            ..where((r) => r.synced.equals(false))
            ..orderBy([
              (r) =>
                  OrderingTerm(expression: r.timestamp, mode: OrderingMode.asc),
              (r) => OrderingTerm(expression: r.id, mode: OrderingMode.asc),
            ])
            ..limit(limit))
          .get();

  Future<SensorReading?> getLatestUnsyncedReading() =>
      (select(sensorReadings)
            ..where((r) => r.synced.equals(false))
            ..orderBy([
              (r) => OrderingTerm(
                expression: r.timestamp,
                mode: OrderingMode.desc,
              ),
              (r) => OrderingTerm(expression: r.id, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();

  @override
  Future<void> clearUnsyncedReadings() async {
    await (delete(
      sensorReadings,
    )..where((row) => row.synced.equals(false))).go();
  }

  /// Removing readings and recording their notice is one transaction: a
  /// background run cannot discard data without leaving a durable UI notice.
  Future<int> dropStaleReadingsWithNotice(DateTime cutoff) =>
      _dropReadingsWithNotice(() => deleteUnsyncedReadingsBefore(cutoff));

  /// All queued samples precede the activation confirmation, even when a
  /// device clock has put their timestamps in the future.
  Future<int> dropUnactivatedReadingsWithNotice() => _dropReadingsWithNotice(
    () =>
        (delete(sensorReadings)..where((row) => row.synced.equals(false))).go(),
  );

  Future<int> _dropReadingsWithNotice(
    Future<int> Function() remove,
  ) => transaction(() async {
    final dropped = await remove();
    if (dropped > 0) {
      // The deletion has acquired this transaction's SQLite writer lock.
      // Add in SQL: never overwrite the count from a client-side snapshot.
      final updated = await customUpdate(
        'UPDATE sync_metadata_entries SET pending_count = pending_count + ? '
        'WHERE sync_table_name = ?',
        variables: [
          Variable.withInt(dropped),
          Variable.withString(staleReadingsNoticeTableName),
        ],
        updates: {syncMetadataEntries},
      );
      if (updated == 0) {
        await into(syncMetadataEntries).insert(
          SyncMetadataEntriesCompanion.insert(
            syncTableName: staleReadingsNoticeTableName,
            pendingCount: Value(dropped),
          ),
        );
      }
    }
    return dropped;
  });

  /// Acknowledge only the count displayed by the UI. New background drops
  /// during that display remain pending for a later notice.
  Future<void> acknowledgeStaleReadings(int displayedCount) =>
      transaction(() async {
        if (displayedCount <= 0) return;
        // Acquire the writer lock before reading any count; subtract only
        // what the user saw, preserving notices from newer background drops.
        await customUpdate(
          'UPDATE sync_metadata_entries SET pending_count = pending_count - ? '
          'WHERE sync_table_name = ?',
          variables: [
            Variable.withInt(displayedCount),
            Variable.withString(staleReadingsNoticeTableName),
          ],
          updates: {syncMetadataEntries},
        );
        await (delete(syncMetadataEntries)..where(
              (row) =>
                  row.syncTableName.equals(staleReadingsNoticeTableName) &
                  row.pendingCount.isSmallerOrEqualValue(0),
            ))
            .go();
      });

  /// Deletes unsynced readings recorded before [cutoff]; returns how many.
  Future<int> deleteUnsyncedReadingsBefore(DateTime cutoff) =>
      (delete(sensorReadings)..where(
            (r) =>
                r.synced.equals(false) & r.timestamp.isSmallerThanValue(cutoff),
          ))
          .go();

  @override
  Future<void> clearPendingImages() async {
    await (delete(
      pendingImages,
    )..where((row) => row.synced.equals(false))).go();
  }

  @override
  Future<void> markReadingsSynced(List<int> ids) async {
    await (update(sensorReadings)..where((r) => r.id.isIn(ids))).write(
      const SensorReadingsCompanion(synced: Value(true)),
    );
  }

  @override
  Future<int> getPendingSyncCount() async {
    final count = sensorReadings.id.count();
    final query = selectOnly(sensorReadings)
      ..where(sensorReadings.synced.equals(false))
      ..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  @override
  Future<SyncMetadataEntry?> getSyncMetadata(String syncTableName) {
    return (select(syncMetadataEntries)
          ..where((row) => row.syncTableName.equals(syncTableName))
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<void> clearSyncMetadata(String syncTableName) async {
    await (delete(
      syncMetadataEntries,
    )..where((row) => row.syncTableName.equals(syncTableName))).go();
  }

  @override
  Future<void> upsertSyncMetadata({
    required String syncTableName,
    required int pendingCount,
    DateTime? lastSyncAt,
    DateTime? lastSyncAttemptAt,
    String? lastSyncError,
  }) async {
    final existing = await getSyncMetadata(syncTableName);

    if (existing == null) {
      await into(syncMetadataEntries).insert(
        SyncMetadataEntriesCompanion.insert(
          syncTableName: syncTableName,
          pendingCount: Value(pendingCount),
          lastSyncAt: Value(lastSyncAt),
          lastSyncAttemptAt: Value(lastSyncAttemptAt),
          lastSyncError: Value(lastSyncError),
        ),
      );
      return;
    }

    await (update(
      syncMetadataEntries,
    )..where((row) => row.id.equals(existing.id))).write(
      SyncMetadataEntriesCompanion(
        pendingCount: Value(pendingCount),
        lastSyncAt: Value(lastSyncAt ?? existing.lastSyncAt),
        lastSyncAttemptAt: Value(
          lastSyncAttemptAt ?? existing.lastSyncAttemptAt,
        ),
        lastSyncError: Value(lastSyncError),
      ),
    );
  }

  // ── Offline data cache ────────────────────────────────────────────────────

  Future<OfflineDataEntry?> getOfflineData(String cacheKey) {
    return (select(offlineDataEntries)
          ..where((row) => row.cacheKey.equals(cacheKey))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> upsertOfflineData(String cacheKey, String payload) async {
    // insertOnConflictUpdate targets the `id` primary key, but the natural
    // key here is the unique cacheKey column — without an explicit target a
    // second write of the same key throws a UNIQUE violation instead of
    // updating (#209).
    await into(offlineDataEntries).insert(
      OfflineDataEntriesCompanion.insert(
        cacheKey: cacheKey,
        payload: payload,
        cachedAt: DateTime.now(),
      ),
      onConflict: DoUpdate(
        (old) => OfflineDataEntriesCompanion(
          payload: Value(payload),
          cachedAt: Value(DateTime.now()),
        ),
        target: [offlineDataEntries.cacheKey],
      ),
    );
  }

  Future<void> deleteOfflineData(String cacheKey) async {
    await (delete(
      offlineDataEntries,
    )..where((row) => row.cacheKey.equals(cacheKey))).go();
  }
}
