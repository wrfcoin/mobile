import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/app.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/collector_provider.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';

import '../test_helpers/fakes.dart';

void main() {
  testWidgets(
    'testnet smoke app shell initializes with controlled sync worker',
    (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'onboarding.completed': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            syncWorkerProvider.overrideWithValue(_FakeSyncWorker()),
            collectorRepositoryProvider.overrideWithValue(
              FakeCollectorRepository(
                reading: SensorReadingModel(
                  latitude: 37.775,
                  longitude: -122.419,
                  pressureHpa: 1012.4,
                  timestamp: DateTime(2026, 5, 30, 12),
                ),
              ),
            ),
            weatherLocationResolverProvider.overrideWithValue(
              FixedWeatherLocationResolver(
                CoarseLocation.round(37.775, -122.419),
              ),
            ),
            weatherRepositoryProvider.overrideWithValue(
              FakeWeatherRepository(),
            ),
            weatherNarrativesProvider.overrideWith(
              () => WeatherNarrativesNotifier()..autoAnalyze = false,
            ),
            walletRepositoryProvider.overrideWithValue(FakeWalletRepository()),
          ],
          child: const WrfcoinApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Weather'), findsWidgets);
    },
  );
}

class _FakeSyncWorker extends SyncWorker {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();

  @override
  Future<SyncRunResult> syncPendingReadings({
    bool includeIdempotencyKey = false,
  }) async {
    return const SyncRunResult(
      acceptedCount: 0,
      failedCount: 0,
      pendingCount: 0,
      reason: SyncRunReason.idle,
    );
  }
}
