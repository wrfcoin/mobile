import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/app_harness.dart';
import '../../../test_helpers/fake_station_backend.dart';

class _Offline implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.none,
  ];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

// Worker normally owns its connection. Here both real UI and worker use the
// same test connection; dispose explicitly between app restarts.
class _Worker extends SyncWorker {
  _Worker(_Db db, DateTime Function() now)
    : super(
        connectivity: _Offline(),
        dbFactory: () => db,
        now: now,
        canStartLogin: false,
        repositoryFactory: (_) =>
            throw StateError('Offline resume must never reach signing or API'),
      );
  Future<SyncRunResult>? resumed;
  @override
  Future<SyncRunResult> syncOnResume({bool includeIdempotencyKey = false}) =>
      resumed = super.syncOnResume(
        includeIdempotencyKey: includeIdempotencyKey,
      );
}

class _Db extends AppDatabase {
  _Db(File file) : super(NativeDatabase(file));
  @override
  Future<void> close() async {}
  Future<void> dispose() => super.close();
}

void main() {
  testWidgets(
    'real app resume at one hour persists expiry notice; dismiss acknowledges only displayed drops',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sol-p-resume-expiry-'),
      ))!;
      final file = File('${directory.path}/readings.sqlite');
      var db = _Db(file);
      var clock = DateTime.utc(2026, 10, 3, 12);
      final capture = clock;
      final backend = FakeStationBackend();
      late _Worker worker;
      Future<void> seed(DateTime time) => db.insertReading(
        SensorReadingsCompanion.insert(
          latitude: 10.1,
          longitude: 20.2,
          pressureHpa: 1013.25,
          timestamp: time,
        ),
      );
      Future<int> count() async =>
          (await db.getSyncMetadata(staleReadingsNoticeTableName))
              ?.pendingCount ??
          0;
      Future<void> mount() async {
        final repository = CollectorRepository(
          sensorDataSource: SensorDataSource(LocationService()),
          batteryMonitor: BatteryMonitor(),
          apiClient: ApiClient(
            dio: backend.buildDio(),
            allowUnauthenticatedRequests: true,
          ),
          db: db,
        );
        worker = _Worker(db, () => clock);
        final harness = await buildTestApp(db: db) as ProviderScope;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...harness.overrides.where(
                (o) =>
                    o.origin != syncWorkerProvider &&
                    o.origin != collectorRepositoryProvider,
              ),
              syncWorkerProvider.overrideWithValue(worker),
              collectorRepositoryProvider.overrideWithValue(repository),
            ],
            child: harness.child,
          ),
        );
        await pumpFrames(tester);
        await tester.tap(find.text('Collect').last);
        await pumpFrames(tester);
      }

      addTearDown(() async {
        await db.dispose();
        await directory.delete(recursive: true);
      });
      await tester.runAsync(() async {
        await seed(capture);
        await seed(capture);
      });
      clock = capture.add(const Duration(seconds: 2999));
      await mount();
      expect(find.text(SyncWorker.staleReadingsNotice(2)), findsNothing);
      expect(await db.getPendingSyncCount(), 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      clock = capture.add(const Duration(seconds: 3600));
      await seed(clock); // Fresh data remains queued; do not extend the existing50-minute client safety cutoff.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(
        worker.resumed,
        isNotNull,
        reason: 'Actual app lifecycle must invoke real resume sync',
      );
      await tester.runAsync(() => worker.resumed!);
      await pumpFrames(tester, frames: 12);
      expect(await count(), 2);
      expect(await db.getPendingSyncCount(), 1);
      expect(find.text(SyncWorker.staleReadingsNotice(2)), findsOneWidget);
      expect(find.textContaining('unable to earn rewards'), findsOneWidget);
      expect(find.text(SyncWorker.earningWindowMessage), findsOneWidget);
      expect(backend.requests, isEmpty);
      expect(backend.statusRequests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => db.dispose());
      db = _Db(file);
      await tester.runAsync(() => db.getPendingSyncCount());
      await mount();
      expect(
        await count(),
        2,
        reason: 'SQLite notice survives real connection/app restart',
      );
      expect(find.text(SyncWorker.staleReadingsNotice(2)), findsOneWidget);
      await seed(capture);
      expect(
        await db.dropStaleReadingsWithNotice(
          clock.subtract(SyncWorker.maxReadingAge),
        ),
        1,
      );
      expect(
        await count(),
        3,
      ); // A background drop newer than the displayed count.
      await tester.tap(find.byTooltip('Dismiss stale readings notice'));
      await tester.runAsync(() => db.getPendingSyncCount());
      await pumpFrames(tester);
      expect(
        await count(),
        1,
        reason: 'Dismiss acknowledges2 displayed drops, preserves1 newer drop',
      );
      expect(
        await db.getPendingSyncCount(),
        1,
        reason: 'Fresh pending reading is unchanged',
      );
      expect(find.text(SyncWorker.staleReadingsNotice(1)), findsOneWidget);
      expect(find.textContaining('WRF settled'), findsNothing);
      expect(backend.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
