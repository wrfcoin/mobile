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
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/collector_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/mobile_station_status_service.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/mobile_station_status_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/station_owner_providers.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/collector_dashboard.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/owner_ledger_banner.dart';
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
    bool canCollect = true,
    MobileStationStatus? stationStatus,
    OwnerLedger? ledger,
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
              AppPreferences(
                consent: ConsentSettings(
                  sensorCollection: canCollect,
                  preciseLocation: canCollect,
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
          if (stationStatus != null)
            mobileStationStatusProvider.overrideWith(
              (ref, owner) async => stationStatus,
            ),
          if (ledger != null)
            ownerStationLedgerProvider.overrideWith((ref) async => ledger),
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

  // The ledger read only starts once the station status has loaded.
  Future<void> settleStatus(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void expectInOrder(WidgetTester tester, List<Finder> sections) {
    final tops = [for (final f in sections) tester.getTopLeft(f).dy];
    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '${sections[i]} should come after ${sections[i - 1]}',
      );
    }
  }

  OwnerLedger ledgerFrozen({int? frozenSince}) => OwnerLedger(
    owner: 'wrf1wallet',
    ownerCommitment: 'c',
    isOwner: true,
    ownerNonce: 0,
    frozenSinceHeight: frozenSince,
    ownerDeactivated: false,
    pendingRecovery: null,
    rewardsSuspended: false,
    consentActive: true,
    actionsActive: true,
    observedAtHeight: 100,
    settledHeight: 100,
  );

  group('section order', () {
    testWidgets('readings and Collect Now open the page; battery and the '
        'upload window notice sit lower', (tester) async {
      await pumpDashboard(
        tester,
        preferencesState: const CollectorPreferencesState(
          isCollecting: true,
          intervalMinutes: 15,
          batteryThreshold: 15,
        ),
        pendingCount: 0,
        wallet: const WalletModel(address: 'wrf1wallet', balance: '0'),
        stationStatus: const MobileStationStatus(MobileStationPhase.onChain),
        ledger: ledgerFrozen(),
      );
      await settleStatus(tester);

      expectInOrder(tester, [
        find.text('Current Readings'),
        find.text('Collect Now'),
        find.byType(Switch),
        find.text('Sync Progress & Rewards'),
        find.text(SyncWorker.earningWindowMessage),
        find.text('Forecast duels'),
        find.text('Battery Impact'),
      ]);
      // On a healthy station nothing sits above the readings.
      final scrollTop = tester.getTopLeft(find.byType(ListView)).dy;
      expect(
        tester.getTopLeft(find.text('Current Readings')).dy - scrollTop,
        lessThan(48),
      );
    });

    testWidgets('the Station ownership card is gone from an on-chain station', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        preferencesState: const CollectorPreferencesState(
          isCollecting: true,
          intervalMinutes: 15,
          batteryThreshold: 15,
        ),
        pendingCount: 0,
        wallet: const WalletModel(address: 'wrf1wallet', balance: '0'),
        stationStatus: const MobileStationStatus(MobileStationPhase.onChain),
        ledger: ledgerFrozen(),
      );
      await settleStatus(tester);

      // The banner shares the card's old condition, so the branch really ran.
      expect(find.byType(OwnerLedgerBanner), findsOneWidget);
      expect(find.text('Station ownership'), findsNothing);
      for (final label in ['Security', 'Transfer', 'Accept']) {
        expect(find.widgetWithText(TextButton, label), findsNothing);
      }
    });

    testWidgets('missing consent and an unregistered station stay above the '
        'readings', (tester) async {
      await pumpDashboard(
        tester,
        preferencesState: const CollectorPreferencesState(
          isCollecting: false,
          intervalMinutes: 15,
          batteryThreshold: 15,
        ),
        pendingCount: 0,
        canCollect: false,
        wallet: const WalletModel(address: 'wrf1wallet', balance: '0'),
        stationStatus: const MobileStationStatus(MobileStationPhase.none),
      );
      await settleStatus(tester);

      expectInOrder(tester, [
        find.text('Review'),
        find.textContaining('Register your phone as a weather station'),
        find.text('Current Readings'),
      ]);
    });

    testWidgets('a frozen station warning stays above the readings', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        preferencesState: const CollectorPreferencesState(
          isCollecting: true,
          intervalMinutes: 15,
          batteryThreshold: 15,
        ),
        pendingCount: 0,
        wallet: const WalletModel(address: 'wrf1wallet', balance: '0'),
        stationStatus: const MobileStationStatus(MobileStationPhase.onChain),
        ledger: ledgerFrozen(frozenSince: 90),
      );
      await settleStatus(tester);

      expectInOrder(tester, [
        find.textContaining('This station is frozen'),
        find.text('Current Readings'),
      ]);
    });

    testWidgets('removed readings stay above the readings; the routine '
        'window notice does not', (tester) async {
      await pumpDashboard(
        tester,
        preferencesState: const CollectorPreferencesState(
          isCollecting: true,
          intervalMinutes: 15,
          batteryThreshold: 15,
        ),
        pendingCount: 0,
        syncMetadata: SyncMetadataEntry(
          id: 1,
          syncTableName: staleReadingsNoticeTableName,
          pendingCount: 2,
        ),
      );
      await settleStatus(tester);

      expectInOrder(tester, [
        find.text(SyncWorker.staleReadingsNotice(2)),
        find.text('Current Readings'),
        find.text(SyncWorker.earningWindowMessage),
      ]);
    });

    testWidgets('a sync failure shows inside the readings card, above Collect '
        'Now', (tester) async {
      await pumpDashboard(
        tester,
        preferencesState: const CollectorPreferencesState(
          isCollecting: true,
          intervalMinutes: 15,
          batteryThreshold: 15,
        ),
        pendingCount: 1,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectorDashboard)),
      );
      final notifier = container.read(collectorProvider.notifier);
      // ignore: invalid_use_of_protected_member
      notifier.state = notifier.state.copyWith(syncMessage: 'Sync failed.');
      await tester.pump();

      expectInOrder(tester, [
        find.text('Current Readings'),
        find.text('Sync failed.'),
        find.text('Collect Now'),
      ]);
    });
  });

  testWidgets('offers Share proof card only for a real commit id', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      preferencesState: const CollectorPreferencesState(
        isCollecting: false,
        intervalMinutes: 15,
        batteryThreshold: 15,
        lastSubmissionId: 'submission-42',
        lastCommitId:
            'c0ffee000000000000000000000000000000000000000000000000004d2a91e7',
      ),
      pendingCount: 0,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('collector-share-proof-card')),
      300,
    );
    expect(find.text('Share proof card'), findsOneWidget);
  });

  testWidgets('no Share proof card without an accepted reading', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      preferencesState: const CollectorPreferencesState(
        isCollecting: false,
        intervalMinutes: 15,
        batteryThreshold: 15,
        lastSubmissionId: 'submission-42',
      ),
      pendingCount: 0,
    );
    await tester.scrollUntilVisible(find.text('Rewards Breakdown'), 300);
    expect(find.text('Share proof card'), findsNothing);
  });

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
    expect(find.text('Low'), findsNothing);
    expect(find.text('Balanced'), findsNothing);
    expect(find.text('Not running'), findsOneWidget);
    expect(find.textContaining('not been measured'), findsOneWidget);
    expect(
      find.textContaining('2.0 samples/hour, pauses below 15%'),
      findsOneWidget,
    );
  });
}
