// Collect screen: the station registrar card (core4 station_registrar_key).
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/background/collection_service.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../../test_helpers/fakes.dart';
import '../../../test_helpers/screenshot_fonts.dart';

import 'package:wrfcoin_mobile/features/collector/data/services/station_registrar_service.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/station_registrar_provider.dart';

class _Worker extends SyncWorker {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();

  @override
  Future<SyncRunResult> syncPendingReadings({
    bool includeIdempotencyKey = false,
  }) async => const SyncRunResult(
    acceptedCount: 0,
    failedCount: 0,
    pendingCount: 0,
    reason: SyncRunReason.idle,
  );
}

class _RunningService extends CollectionServiceController {
  @override
  bool get supported => true;
  @override
  Future<bool> get isRunning async => true;
  @override
  Future<bool?> get isBatteryLimited async => false;
  @override
  void Function() listen(
    void Function() onStopped, {
    void Function()? onTick,
  }) => () {};
}

// A wallet whose derived phone station id parses (a 0x chain address).
class _ChainWallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => const WalletModel(
    address: '0x791026e25cc1ba461167ffb5c6dc095c284bd92c',
    balance: '150000000',
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required MobileStationPhase phase,
  required RegistrarStatus? registrar,
}) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  await const CollectorPreferences().save(
    const CollectorPreferencesState(
      isCollecting: true,
      intervalMinutes: 15,
      batteryThreshold: 15,
      syncedSubmissionCount: 0,
    ),
  );
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const CollectorDashboard())],
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
              timestamp: DateTime(2026, 11, 1, 12),
            ),
          ),
        ),
        syncWorkerProvider.overrideWithValue(_Worker()),
        collectionServiceProvider.overrideWithValue(_RunningService()),
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
        walletProvider.overrideWith(_ChainWallet.new),
        keyManagerProvider.overrideWithValue(
          KeyManager(
            biometric: BiometricService(client: FakeLocalAuthClient()),
            storage: InMemoryKeyValueStorage(),
          ),
        ),
        challengeRepositoryProvider.overrideWithValue(
          FakeChallengeRepository(),
        ),
        ownerStationLedgerProvider.overrideWith(
          (ref) async => const OwnerLedger(
            owner: '0x791026e25cc1ba461167ffb5c6dc095c284bd92c',
            ownerCommitment: 'c',
            isOwner: true,
            ownerNonce: 0,
            frozenSinceHeight: null,
            ownerDeactivated: false,
            pendingRecovery: null,
            rewardsSuspended: false,
            consentActive: true,
            actionsActive: true,
            observedAtHeight: 100,
            settledHeight: 100,
          ),
        ),
        mobileStationStatusProvider.overrideWith(
          (ref, owner) async => MobileStationStatus(phase),
        ),
        stationRegistrarStatusProvider.overrideWith(
          (ref, id) async => registrar,
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        theme: ThemeData(fontFamily: 'Roboto'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final card = find.byKey(const Key('station-registrar-card'));

  group('the registrar card on the Collect screen', () {
    for (final (name, phase, registrar, shown)
        in <(String, MobileStationPhase, RegistrarStatus?, bool)>[
          (
            'waiting + open',
            MobileStationPhase.dbOnly,
            RegistrarStatus.notRequested,
            true,
          ),
          (
            'waiting + requests not open',
            MobileStationPhase.dbOnly,
            null,
            false,
          ),
          (
            'already in a batch',
            MobileStationPhase.submitted,
            RegistrarStatus.notRequested,
            false,
          ),
          (
            'on chain',
            MobileStationPhase.onChain,
            RegistrarStatus.notRequested,
            false,
          ),
          (
            'not registered with the backend',
            MobileStationPhase.none,
            RegistrarStatus.notRequested,
            false,
          ),
        ]) {
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(390, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pumpDashboard(tester, phase: phase, registrar: registrar);
        expect(card, shown ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });

  // PR screenshots. Skipped unless SCREENSHOT_FONT_DIR is set (text rendering
  // differs per platform). To regenerate:
  //   SCREENSHOT_FONT_DIR=$FLUTTER/bin/cache/artifacts/material_fonts \
  //     flutter test --update-goldens \
  //     test/features/collector/presentation/station_registrar_screenshots_test.dart
  final fonts = Platform.environment['SCREENSHOT_FONT_DIR'] != null;
  for (final (shot, registrar) in <(String, RegistrarStatus)>[
    ('registrar-offer', RegistrarStatus.notRequested),
    (
      'registrar-held',
      RegistrarStatus(
        RegistrarState.held,
        releaseAt: DateTime.utc(2026, 11, 22, 20),
      ),
    ),
  ]) {
    for (final (width, size) in const [
      ('phone-390', Size(390, 1100)),
      ('desktop-1280', Size(1280, 900)),
    ]) {
      testWidgets('$shot $width', skip: !fonts, (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(loadScreenshotFonts);
        await _pumpDashboard(
          tester,
          phase: MobileStationPhase.dbOnly,
          registrar: registrar,
        );
        expect(card, findsOneWidget);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../../docs/screens/station-registrar/$shot-$width.png',
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
