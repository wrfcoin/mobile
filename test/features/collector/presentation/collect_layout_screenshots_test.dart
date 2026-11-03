// Renders the PR screenshots. Skipped unless SCREENSHOT_FONT_DIR is set,
// because text rendering differs per platform. To regenerate:
//   SCREENSHOT_FONT_DIR=$FLUTTER/bin/cache/artifacts/material_fonts \
//     flutter test --update-goldens \
//     test/features/collector/presentation/collect_layout_screenshots_test.dart
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
import 'package:wrfcoin_mobile/features/settings/presentation/screens/app_settings_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/background/collection_service.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../../test_helpers/fakes.dart';
import '../../../test_helpers/screenshot_fonts.dart';

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

class _Wallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async =>
      const WalletModel(address: 'wrf1wallet', balance: '150000000');
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

final _shots = <(String, Widget, bool, MobileStationPhase)>[
  (
    'collect-healthy',
    const CollectorDashboard(),
    true,
    MobileStationPhase.onChain,
  ),
  (
    'collect-stopped',
    const CollectorDashboard(),
    true,
    MobileStationPhase.onChain,
  ),
  (
    'collect-blocked',
    const CollectorDashboard(),
    false,
    MobileStationPhase.none,
  ),
  (
    'settings-station',
    const AppSettingsScreen(),
    true,
    MobileStationPhase.onChain,
  ),
];

void main() {
  final fonts = Platform.environment['SCREENSHOT_FONT_DIR'] != null;
  for (final (shot, screen, consent, phase) in _shots) {
    for (final (width, size) in const [
      ('phone-390', Size(390, 2150)),
      ('desktop-1280', Size(1280, 1600)),
    ]) {
      testWidgets('$shot $width', skip: !fonts, (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(loadScreenshotFonts);
        SharedPreferences.setMockInitialValues(const <String, Object>{});
        await const CollectorPreferences().save(
          CollectorPreferencesState(
            isCollecting: consent,
            intervalMinutes: 15,
            batteryThreshold: 15,
            syncedSubmissionCount: 3,
          ),
        );
        final prefs = await SharedPreferences.getInstance();
        final router = GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => screen)],
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
                  AppPreferences(
                    consent: ConsentSettings(
                      sensorCollection: consent,
                      preciseLocation: consent,
                    ),
                  ),
                ),
              ),
              walletProvider.overrideWith(_Wallet.new),
              keyManagerProvider.overrideWithValue(
                KeyManager(
                  biometric: BiometricService(client: FakeLocalAuthClient()),
                  storage: InMemoryKeyValueStorage(),
                ),
              ),
              challengeRepositoryProvider.overrideWithValue(
                FakeChallengeRepository(),
              ),
              // A healthy ledger: nothing frozen, no recovery pending.
              ownerStationLedgerProvider.overrideWith(
                (ref) async => const OwnerLedger(
                  owner: 'wrf1wallet',
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
        if (consent && screen is CollectorDashboard) {
          final notifier = ProviderScope.containerOf(
            tester.element(find.byType(CollectorDashboard)),
          ).read(collectorProvider.notifier);
          // ignore: invalid_use_of_protected_member
          notifier.state = notifier.state.copyWith(
            currentReading: SensorReadingModel(
              latitude: 37.775,
              longitude: -122.419,
              pressureHpa: 1012.4,
              timestamp: DateTime(2026, 11, 1, 12),
            ),
            serviceSupported: true,
            serviceRunning: true,
            lastReadingAt: DateTime.now().subtract(
              shot == 'collect-stopped'
                  ? const Duration(hours: 9)
                  : const Duration(minutes: 6),
            ),
            serviceRestartedAt: shot == 'collect-stopped'
                ? DateTime.now()
                : null,
          );
          await tester.pump();
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../../docs/screens/collect-layout/$shot-$width.png',
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
