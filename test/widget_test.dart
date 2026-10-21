import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';

import 'test_helpers/fakes.dart';

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
      pendingCount: 0,
      reason: SyncRunReason.idle,
    );
  }
}

void main() {
  testWidgets('App renders with bottom navigation', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'onboarding.completed': true,
      // The Profile tab is gated behind the achievements flag (#142);
      // enable it so all five tabs render.
      'ff_enableAchievementsUi': true,
    });
    final prefs = await SharedPreferences.getInstance();

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
            ),
          ),
          syncWorkerProvider.overrideWithValue(_FakeSyncWorker()),
          weatherLocationResolverProvider.overrideWithValue(
            FixedWeatherLocationResolver(
              CoarseLocation.round(37.775, -122.419),
            ),
          ),
          weatherRepositoryProvider.overrideWithValue(FakeWeatherRepository()),
          weatherNarrativesProvider.overrideWith(
            () => WeatherNarrativesNotifier()..autoAnalyze = false,
          ),
        ],
        child: const WrfcoinApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Bottom navigation bar should have all 5 tabs
    final bottomNav = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(bottomNav.items.length, 5);
    expect(bottomNav.items[0].label, 'Weather');
    expect(bottomNav.items[1].label, 'Collect');
    expect(bottomNav.items[2].label, 'Earnings');
    expect(bottomNav.items[3].label, 'Govern');
    expect(bottomNav.items[4].label, 'Profile');
  });
}
