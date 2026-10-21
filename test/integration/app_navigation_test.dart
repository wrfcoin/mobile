import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/app.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
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
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../test_helpers/fakes.dart';

class _FakeSyncWorker extends SyncWorker {
  _FakeSyncWorker();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();

  @override
  Future<SyncRunResult> syncPendingReadings({bool includeIdempotencyKey = false}) async {
    return const SyncRunResult(
      acceptedCount: 0,
      failedCount: 0,
      pendingCount: 2,
      reason: SyncRunReason.idle,
    );
  }
}

void main() {
  testWidgets('navigates across all five tabs', (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'onboarding.completed': true,
      // Profile is reachable using the default feature flags.
    });

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
              pendingCount: 2,
            ),
          ),
          challengeRepositoryProvider.overrideWithValue(
            FakeChallengeRepository(),
          ),
          syncWorkerProvider.overrideWithValue(_FakeSyncWorker()),
          weatherNarrativesProvider.overrideWith(
            () => WeatherNarrativesNotifier()..autoAnalyze = false,
          ),
          weatherLocationResolverProvider.overrideWithValue(
            FixedWeatherLocationResolver(
              CoarseLocation.round(37.775, -122.419),
            ),
          ),
          weatherRepositoryProvider.overrideWithValue(
            FakeWeatherRepository(
              alerts: const [
                AlertModel(
                  id: 'alert-1',
                  type: 'Wind Advisory',
                  severity: 'moderate',
                  location: 'Local',
                  timestamp: '2026-03-10T00:00:00Z',
                  description: 'Gusty winds expected',
                ),
              ],
            ),
          ),
          governanceRepositoryProvider.overrideWithValue(
            FakeGovernanceRepository(
              proposals: const [
                ProposalModel(
                  id: 'prop-1',
                  title: 'Upgrade',
                  description: 'Ship the upgrade',
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
          walletSecureStorageProvider.overrideWithValue(
            FakeWalletSecureStorage(),
          ),
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: keyStorage,
            ),
          ),
        ],
        child: const WrfcoinApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Weather'), findsWidgets);

    await tester.tap(find.text('Collect'));
    await tester.pumpAndSettle();
    expect(find.text('Collect'), findsWidgets);
    expect(find.text('Sync Progress & Rewards'), findsOneWidget);

    // The stored wallet has no session: Earnings offers Sign in (mobile#320)
    // and the other tabs stay reachable.
    await tester.tap(find.text('Earnings'));
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.byKey(const Key('wallet-sign-in')), findsOneWidget);

    await tester.tap(find.text('Govern'));
    await tester.pumpAndSettle();
    expect(find.text('Proposals'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Achievements'), findsWidgets);
  });
}
