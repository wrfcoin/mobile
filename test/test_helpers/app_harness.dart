import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/app.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/challenges/data/repositories/challenge_repository.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/achievement_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/leaderboard_entry_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/alert_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/observability/crash_report_store.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import 'fakes.dart';

AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

/// Bounded stand-in for [WidgetTester.pumpAndSettle].
///
/// The app schedules periodic timers that never settle, so `pumpAndSettle`
/// times out (see the pump+fixed-duration convention used across this test
/// suite). Pump a fixed number of frames instead — enough to cover route
/// transitions and dialog animations.
Future<void> pumpFrames(WidgetTester tester, {int frames = 4}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Pumps bounded frames until [finder] matches at least one widget.
///
/// Use after navigation taps in place of `pumpAndSettle` (see [pumpFrames])
/// when the next assertion needs a widget from the destination route.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 30,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Widget not found after $maxFrames frames: $finder');
}

Future<Widget> buildTestApp({
  required AppDatabase db,
  AppPreferencesStore? preferencesStore,
  ForecastModel? forecast,
  List<AlertModel> alerts = const <AlertModel>[
    AlertModel(
      id: 'alert-1',
      type: 'Wind Advisory',
      severity: 'moderate',
      location: 'Local',
      timestamp: '2026-03-10T00:00:00Z',
      description: 'Gusty winds expected',
    ),
  ],
  // Appended after the harness overrides, e.g. a recording data source.
  List<Override> extraOverrides = const <Override>[],
  // A stored wallet session. Only tests about the loaded wallet tab need
  // it; the default is a wallet that is not signed in.
  bool signedIn = false,
  // The wallet key's biometric prompt, e.g. one that counts prompts.
  LocalAuthClient? localAuthClient,
}) async {
  // Ensure onboarding is marked complete so it does not block navigation in tests.
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarding.completed', true);

  final keyStorage = InMemoryKeyValueStorage();
  await keyStorage.write(
    key: 'wrf_address',
    value: '0x1234567890abcdef1234567890abcdef12345678',
  );
  if (signedIn) {
    // Automatic callers never start a wallet login (mobile#320), so only a
    // stored session shows the loaded wallet tab. Without one the wallet
    // tab says "Not signed in" and every other tab works as usual.
    await keyStorage.write(key: 'wrf_jwt', value: 'jwt-test-session');
    await keyStorage.write(
      key: 'wrf_jwt_expires_at',
      value: DateTime.utc(2100).millisecondsSinceEpoch.toString(),
    );
  }

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (preferencesStore != null)
        appPreferencesStoreProvider.overrideWithValue(preferencesStore),
      appDatabaseProvider.overrideWithValue(db),
      // App-shell fixtures must not inspect the host's app-support directory.
      // Dedicated diagnostics tests use their own temporary file store.
      localCrashReportStoreProvider.overrideWith((ref) async => null),
      syncWorkerProvider.overrideWithValue(FakeSyncWorker()),
      weatherNarrativesProvider.overrideWith(
        () => WeatherNarrativesNotifier()..autoAnalyze = false,
      ),
      collectorRepositoryProvider.overrideWithValue(
        FakeCollectorRepository(
          reading: SensorReadingModel(
            latitude: 37.775,
            longitude: -122.419,
            pressureHpa: 1012.4,
            timestamp: DateTime(2026, 3, 10, 12),
          ),
          pendingCount: 2,
        ),
      ),
      challengeRepositoryProvider.overrideWithValue(FakeChallengeRepository()),
      weatherLocationResolverProvider.overrideWithValue(
        FixedWeatherLocationResolver(CoarseLocation.round(37.775, -122.419)),
      ),
      weatherRepositoryProvider.overrideWithValue(
        FakeWeatherRepository(
          forecast:
              forecast ??
              const ForecastModel(
                temperature: 20,
                humidity: 55,
                pressure: 1013.25,
                windSpeed: 18,
                precipitation: 4,
                location: 'San Francisco',
                timestamp: '2026-03-10T13:30:00Z',
              ),
          alerts: alerts,
        ),
      ),
      governanceRepositoryProvider.overrideWithValue(
        FakeGovernanceRepository(
          proposals: const [
            ProposalModel(
              id: 'prop-1',
              title: 'Upgrade',
              description: 'Ship the upgrade',
              createdAt: '2026-03-10T00:00:00Z',
            ),
          ],
        ),
      ),
      gamificationRepositoryProvider.overrideWithValue(
        FakeGamificationRepository(
          achievements: const [
            AchievementModel(
              id: 'ach-1',
              name: 'First Reading',
              description: 'Started collecting',
              tier: 'bronze',
              progress: 1,
              earned: true,
            ),
          ],
          leaderboard: const [
            LeaderboardEntry(
              rank: 1,
              name: 'Alice',
              score: '10',
              metricLabel: 'achievements',
              subtitle: 'NA',
            ),
          ],
        ),
      ),
      walletRepositoryProvider.overrideWithValue(
        FakeWalletRepository(
          transactions: const [
            TransactionModel(
              hash: '0x1',
              timestamp: '2026-03-10T00:00:00Z',
              from: 'wrf1234567890abcdef1234',
              to: 'wrf0000000000000000000000',
              value: '10',
            ),
          ],
        ),
      ),
      walletSecureStorageProvider.overrideWithValue(FakeWalletSecureStorage()),
      keyManagerProvider.overrideWithValue(
        KeyManager(
          biometric: BiometricService(
            client: localAuthClient ?? FakeLocalAuthClient(),
          ),
          storage: keyStorage,
        ),
      ),
      ...extraOverrides,
    ],
    child: const WrfcoinApp(),
  );
}
