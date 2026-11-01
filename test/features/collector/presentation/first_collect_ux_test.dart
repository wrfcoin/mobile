import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/localization/app_localizations.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/challenges/data/repositories/challenge_repository.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/battery_monitor.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/collector_dashboard.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/privacy_center_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fakes.dart';
import '../../../test_helpers/fake_station_backend.dart';

class _Wallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async =>
      const WalletModel(address: syntheticAddress, balance: '0');
}

class _BackgroundWork extends WorkmanagerPlatform {
  final cancelled = <String>[];
  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelled.add(uniqueName);
  }
}

class _Worker extends SyncWorker {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

void main() {
  late AppDatabase db;
  late int statusCalls;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    statusCalls = 0;
  });
  tearDown(() async {
    await db.close();
  });

  Future<void> pump(
    WidgetTester tester,
    String? status, {
    int dropped = 0,
    bool privacy = false,
  }) async {
    if (dropped > 0) {
      await db.upsertSyncMetadata(
        syncTableName: 'sensor_readings_stale_notice',
        pendingCount: dropped,
      );
    }
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.path.endsWith('/ownership')) {
              // Owner-ledger banner (station theft protection): unavailable
              // here; it must show nothing, and is not a status call.
              h.reject(
                DioException.badResponse(
                  statusCode: 503,
                  requestOptions: o,
                  response: Response<dynamic>(
                    requestOptions: o,
                    statusCode: 503,
                    data: <String, dynamic>{},
                  ),
                ),
              );
              return;
            }
            statusCalls++;
            expect(o.method, 'GET');
            expect(o.path, '/weather/stations/mobile');
            final code = status == null ? 404 : 200;
            final response = Response<dynamic>(
              requestOptions: o,
              statusCode: code,
              data: status == null
                  ? {
                      'error': {'code': 'NOT_REGISTERED'},
                    }
                  : {'stationId': syntheticStationId, 'status': status},
            );
            if (code == 404) {
              h.reject(
                DioException.badResponse(
                  statusCode: code,
                  requestOptions: o,
                  response: response,
                ),
              );
            } else {
              h.resolve(response);
            }
          },
        ),
      );
    final api = ApiClient(dio: dio, allowUnauthenticatedRequests: true);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          apiClientProvider.overrideWithValue(api),
          collectorRepositoryProvider.overrideWithValue(
            CollectorRepository(
              sensorDataSource: SensorDataSource(LocationService()),
              batteryMonitor: BatteryMonitor(),
              apiClient: api,
              db: db,
            ),
          ),
          walletProvider.overrideWith(() => _Wallet()),
          syncWorkerProvider.overrideWithValue(_Worker()),
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(const AppPreferences()),
          ),
          appLoggerProvider.overrideWithValue(
            const AppLogger(sinks: [], verbose: false),
          ),
          challengeRepositoryProvider.overrideWithValue(
            FakeChallengeRepository(),
          ),
          // Friend Challenges is on by default, so the dashboard reads the
          // wallet address; keep it off the platform secure storage.
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: InMemoryKeyValueStorage(),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: privacy
              ? const PrivacyCenterScreen()
              : const CollectorDashboard(),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  testWidgets('Collect explains the upload and earning windows before expiry', (
    tester,
  ) async {
    await pump(tester, 'on_chain');
    expect(find.textContaining('50 minutes'), findsOneWidget);
    expect(find.textContaining('one hour'), findsOneWidget);
    expect(find.textContaining('do not guarantee rewards'), findsOneWidget);
    expect(find.byTooltip('Dismiss stale readings notice'), findsNothing);
  });

  testWidgets('revoke all collection consent clears the durable stale notice', (
    tester,
  ) async {
    Workmanager(); // Resolve the platform once, then replace it with a test stub.
    final originalPlatform = WorkmanagerPlatform.instance;
    final background = _BackgroundWork();
    WorkmanagerPlatform.instance = background;
    addTearDown(() => WorkmanagerPlatform.instance = originalPlatform);
    await pump(tester, null, dropped: 3, privacy: true);
    expect(
      (await db.getSyncMetadata(staleReadingsNoticeTableName))?.pendingCount,
      3,
    );
    await tester.scrollUntilVisible(
      find.text('Revoke All Collection Consent'),
      300,
    );
    await tester.tap(find.text('Revoke All Collection Consent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(background.cancelled, hasLength(2));
    expect(await db.getSyncMetadata(staleReadingsNoticeTableName), isNull);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PrivacyCenterScreen)),
    );
    expect(container.read(collectorProvider).staleReadingsCount, 0);
    await container.read(collectorProvider.notifier).collectNow();
    expect(container.read(collectorProvider).staleReadingsCount, 0);
  });

  for (final status in ['db_only', 'submitted']) {
    testWidgets('$status shows pending activation with paused uploads', (
      tester,
    ) async {
      await pump(tester, status);
      expect(statusCalls, 1);
      expect(
        find.text(
          'Station awaiting activation. Rewards start once the network activates your station.',
        ),
        findsOneWidget,
      );
    });
  }
  testWidgets('on_chain uses normal Collect without pending activation', (
    tester,
  ) async {
    await pump(tester, 'on_chain');
    expect(statusCalls, 1);
    expect(find.textContaining('Rewards start once'), findsNothing);
  });
  testWidgets('unregistered phone explains the one-time wallet approval', (
    tester,
  ) async {
    await pump(tester, null);
    expect(statusCalls, 1);
    expect(
      find.textContaining('Register your phone as a weather station'),
      findsOneWidget,
    );
  });
  testWidgets(
    'background stale notice remains visible and is acknowledged once',
    (tester) async {
      await pump(tester, 'db_only', dropped: 3);
      expect(find.text(SyncWorker.staleReadingsNotice(3)), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss stale readings notice'));
      await tester.pump();
      expect(find.text(SyncWorker.staleReadingsNotice(3)), findsNothing);
      expect(await db.getSyncMetadata('sensor_readings_stale_notice'), isNull);
    },
  );
}
