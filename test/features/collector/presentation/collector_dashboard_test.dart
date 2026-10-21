import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/localization/app_localizations.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/challenges/data/repositories/challenge_repository.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/collector_dashboard.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fakes.dart';

class _FakeSyncWorker extends SyncWorker {
  _FakeSyncWorker(this._result);

  final SyncRunResult _result;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();

  @override
  Future<SyncRunResult> syncPendingReadings({
    bool includeIdempotencyKey = false,
  }) async => _result;
}

class _NullWalletNotifier extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => null;
}

class _ReportedWalletNotifier extends WalletNotifier {
  _ReportedWalletNotifier(this.wallet);
  final WalletModel wallet;
  @override
  Future<WalletModel?> build() async => wallet;
}

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester, {
    required CollectorPreferencesState preferencesState,
    required int pendingCount,
    SyncMetadataEntry? syncMetadata,
    WalletModel? wallet,
  }) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await const CollectorPreferences().save(preferencesState);
    final prefs = await SharedPreferences.getInstance();

    final keyStorage = InMemoryKeyValueStorage();
    await keyStorage.write(
      key: 'wrf_address',
      value: '0x1234567890abcdef1234567890abcdef12345678',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          collectorRepositoryProvider.overrideWithValue(
            FakeCollectorRepository(
              reading: SensorReadingModel(
                latitude: 37.775,
                longitude: -122.419,
                pressureHpa: 1012.4,
                timestamp: DateTime(2026, 3, 10, 12),
              ),
              pendingCount: pendingCount,
              syncMetadata: syncMetadata,
            ),
          ),
          syncWorkerProvider.overrideWithValue(
            _FakeSyncWorker(
              const SyncRunResult(
                acceptedCount: 0,
                failedCount: 0,
                pendingCount: 0,
                reason: SyncRunReason.idle,
              ),
            ),
          ),
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(
              const AppPreferences(
                consent: ConsentSettings(
                  sensorCollection: true,
                  preciseLocation: true,
                ),
              ),
            ),
          ),
          walletProvider.overrideWith(
            () => wallet == null
                ? _NullWalletNotifier()
                : _ReportedWalletNotifier(wallet),
          ),
          challengeRepositoryProvider.overrideWithValue(
            FakeChallengeRepository(),
          ),
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: keyStorage,
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CollectorDashboard(),
        ),
      ),
    );

    // Use pump instead of pumpAndSettle because ChallengesNotifier has a
    // Timer.periodic that prevents pumpAndSettle from completing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows reward unavailable copy when backend returns no totals', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      preferencesState: const CollectorPreferencesState(
        isCollecting: true,
        intervalMinutes: 15,
        batteryThreshold: 15,
        syncedSubmissionCount: 3,
        lastSubmissionId: 'submission-42',
        lastSubmissionStatus: 'pending',
      ),
      pendingCount: 1,
      syncMetadata: SyncMetadataEntry(
        id: 1,
        syncTableName: sensorReadingsSyncTableName,
        pendingCount: 1,
        lastSyncAt: DateTime(2026, 3, 10, 12),
        lastSyncError: 'pending sync metadata',
      ),
    );

    await tester.scrollUntilVisible(find.text('Rewards Breakdown'), 300);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Reward totals unavailable until the backend returns them.'),
      findsOneWidget,
    );
    expect(find.textContaining('0.00 WRF settled'), findsNothing);
  });

  testWidgets(
    'wallet without reward fields shows unavailable breakdown with a real zero balance',
    (tester) async {
      await pumpDashboard(
        tester,
        preferencesState: const CollectorPreferencesState(
          isCollecting: false,
          intervalMinutes: 15,
          batteryThreshold: 15,
        ),
        pendingCount: 0,
        wallet: const WalletModel(address: 'wrf1wallet', balance: '0'),
      );
      await tester.scrollUntilVisible(find.text('Rewards Breakdown'), 300);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Not available'), findsNWidgets(3));
      expect(find.text('0 WRF'), findsOneWidget);
    },
  );

  testWidgets('reported reward and unavailable reward remain distinct', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      preferencesState: const CollectorPreferencesState(
        isCollecting: false,
        intervalMinutes: 15,
        batteryThreshold: 15,
      ),
      pendingCount: 0,
      wallet: const WalletModel(
        address: 'wrf1wallet',
        balance: '0',
        weatherRewards: '892000000',
      ),
    );
    await tester.scrollUntilVisible(find.text('Rewards Breakdown'), 300);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Not available'), findsNWidgets(2));
    expect(find.text('8.92 WRF'), findsOneWidget);
    expect(find.text('0 WRF'), findsOneWidget);
  });

  for (final available in [true, false]) {
    testWidgets(
      'chain reward totals and unavailable reasons on Collect ($available)',
      (tester) async {
        await pumpDashboard(
          tester,
          preferencesState: const CollectorPreferencesState(
            isCollecting: false,
            intervalMinutes: 15,
            batteryThreshold: 15,
          ),
          pendingCount: 0,
          wallet: WalletModel.fromJson({
            'address': 'wrf1wallet',
            'balance': '0',
            'earnedBalanceTotal': '700000000',
            'weatherRewards': available ? '125000000' : null,
            'weatherRewardsPending': available ? '25000000' : null,
            'weatherRewardsUnavailable': available
                ? 'STALE REASON MUST BE HIDDEN'
                : 'This node does not report contribution rewards.',
          }),
        );
        await tester.scrollUntilVisible(find.text('Rewards Breakdown'), 300);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Total earned'), findsOneWidget);
        expect(find.text('7 WRF'), findsOneWidget);
        expect(find.text('Network Bonus'), findsNothing);
        if (available) {
          expect(find.text('1.25 WRF'), findsOneWidget);
          expect(find.text('0.25 WRF'), findsOneWidget);
          expect(find.textContaining('Not available'), findsNothing);
          expect(find.textContaining('STALE REASON'), findsNothing);
          expect(
            find.textContaining('Reward totals unavailable'),
            findsNothing,
          );
        } else {
          expect(
            find.textContaining(
              'This node does not report contribution rewards.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Not available'), findsWidgets);
        }
      },
    );
  }

  testWidgets('shows settled WRF only when reward totals are available', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      preferencesState: const CollectorPreferencesState(
        isCollecting: true,
        intervalMinutes: 15,
        batteryThreshold: 15,
        syncedSubmissionCount: 5,
        rewardTotalsAvailable: true,
        earnedRewardWrf: 4.25,
      ),
      pendingCount: 0,
    );

    await tester.scrollUntilVisible(find.text('Rewards Breakdown'), 300);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('4.25 WRF settled'), findsOneWidget);
    expect(
      find.text('Reward totals unavailable until the backend returns them.'),
      findsNothing,
    );
  });

  for (final (baseUnits, wrf) in [
    ('150000000', '1.5'),
    ('9007199254740993123456789', '90071992547409931.23456789'),
  ]) {
    testWidgets('Collect live balance converts $baseUnits exactly', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        preferencesState: const CollectorPreferencesState(
          isCollecting: false,
          intervalMinutes: 15,
          batteryThreshold: 15,
        ),
        pendingCount: 0,
        wallet: WalletModel(address: 'wrf1wallet', balance: baseUnits),
      );
      await tester.scrollUntilVisible(find.text('Live balance'), 300);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('$wrf WRF'), findsOneWidget);
      expect(find.textContaining('credits'), findsNothing);
    });
  }

  testWidgets('shows estimated battery impact for adaptive sampling', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      preferencesState: const CollectorPreferencesState(
        isCollecting: true,
        intervalMinutes: 30,
        batteryThreshold: 15,
      ),
      pendingCount: 0,
    );

    expect(find.text('Battery Impact'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(
      find.textContaining('2.0 samples/hour, pauses below 15%'),
      findsOneWidget,
    );
  });
}
