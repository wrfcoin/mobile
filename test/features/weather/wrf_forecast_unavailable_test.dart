import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/wrf_forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/wrf_forecast_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_dashboard.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/hdd_cdd_card.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/wrf_forecast_chart.dart';

import '../../test_helpers/fakes.dart';

/// mobile#269: no forecast value under the WRF heading may originate on the
/// device. The dashboard makes no WRF request (the backend has no
/// wrf-forecast route) and shows an explicit unavailable card; a failing
/// fetch keeps it unavailable; a real response yields the chart with the
/// server's values.
WrfForecastModel serverForecast({double tempC = 27.25}) => WrfForecastModel(
  location: 'local',
  generatedAt: '2026-09-26T00:00:00Z',
  ipfsCid: 'bafyserverrealcid',
  hourly: [
    WrfForecastPoint(
      timestamp: '2026-09-26T01:00:00Z',
      temperatureC: tempC,
      temperatureMaxC: tempC + 1,
      temperatureMinC: tempC - 1,
      precipitationMm: 0.4,
      windSpeedMs: 2.2,
      forecastConfidence: 0.9,
      hdd: 0,
      cdd: tempC - 18.3,
    ),
  ],
);

final area = CoarseLocation.round(44.98, -93.27);

Future<ProviderContainer> pumpDashboard(
  WidgetTester tester,
  Either<Failure, WrfForecastModel> Function(CoarseLocation) wrf,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weatherLocationResolverProvider.overrideWithValue(
          FixedWeatherLocationResolver(area),
        ),
        weatherRepositoryProvider.overrideWithValue(
          FakeWeatherRepository(wrfForecast: wrf),
        ),
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
        weatherNarrativesProvider.overrideWith(
          () => WeatherNarrativesNotifier()..autoAnalyze = false,
        ),
      ],
      child: const MaterialApp(home: ForecastDashboard()),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ProviderScope.containerOf(
    tester.element(find.byType(ForecastDashboard)),
  );
}

Future<void> loadWrf(WidgetTester tester, ProviderContainer container) async {
  await container.read(wrfForecastProvider.notifier).loadWrfForecast(area);
  await tester.pump();
}

final unavailableCard = find.byType(WrfUnavailableCard, skipOffstage: false);
final chart = find.byType(WrfForecastChart, skipOffstage: false);
final hddCdd = find.byType(HddCddCard, skipOffstage: false);

void main() {
  const failures = <String, Failure>{
    '404': ServerFailure('Not found', statusCode: 404),
    '401': AuthFailure(),
    'timeout': NetworkFailure('Connection timed out'),
  };
  testWidgets('dashboard makes no WRF request and shows the unavailable card', (
    tester,
  ) async {
    var requests = 0;
    final container = await pumpDashboard(tester, (_) {
      requests++;
      return Right(serverForecast());
    });

    expect(requests, 0);
    expect(unavailableCard, findsOneWidget);
    expect(chart, findsNothing);
    expect(hddCdd, findsNothing);
    expect(container.read(wrfForecastProvider).data, isNull);
  });

  failures.forEach((label, failure) {
    testWidgets('$label: unavailable card, no chart and no values', (
      tester,
    ) async {
      final container = await pumpDashboard(tester, (_) => Left(failure));
      await loadWrf(tester, container);

      expect(unavailableCard, findsOneWidget);
      expect(chart, findsNothing);
      expect(hddCdd, findsNothing);
      expect(
        find.textContaining('SIMULATED', skipOffstage: false),
        findsNothing,
      );
      final state = container.read(wrfForecastProvider);
      expect(state.data, isNull, reason: 'nothing generated on the device');
      expect(state.unavailable, isTrue);
      expect(state.unavailableReason, failure.message);
    });
  });

  testWidgets('200: chart with the server values, no unavailable card', (
    tester,
  ) async {
    final forecast = serverForecast();
    final container = await pumpDashboard(tester, (_) => Right(forecast));
    await loadWrf(tester, container);

    expect(unavailableCard, findsNothing);
    expect(chart, findsOneWidget);
    expect(tester.widget<WrfForecastChart>(chart).forecast, forecast);
    expect(container.read(wrfForecastProvider).data, forecast);
    expect(container.read(wrfForecastProvider).unavailable, isFalse);
  });

  testWidgets('previous real data is retained on refresh failure', (
    tester,
  ) async {
    final forecast = serverForecast(tempC: 21.5);
    var fail = false;
    final container = await pumpDashboard(
      tester,
      (_) => fail ? const Left(NetworkFailure()) : Right(forecast),
    );
    await loadWrf(tester, container);
    expect(container.read(wrfForecastProvider).data, forecast);

    fail = true;
    await loadWrf(tester, container);

    final state = container.read(wrfForecastProvider);
    expect(state.unavailable, isTrue);
    expect(
      state.data,
      forecast,
      reason: 'the last server response, not a stub',
    );
    expect(chart, findsOneWidget);
    expect(tester.widget<WrfForecastChart>(chart).forecast, forecast);
    expect(unavailableCard, findsNothing);
  });

  test('source guard: lib/ has no device-side WRF forecast generator', () {
    const banned = <String>[
      'wrfForecastSimulationStub',
      // the stub's all-zero placeholder CID
      'Qm000000000000000000000000000000000000000000000',
    ];
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final symbol in banned) {
        if (text.contains(symbol)) offenders.add('${entity.path}: $symbol');
      }
    }
    expect(offenders, isEmpty);
  });
}
