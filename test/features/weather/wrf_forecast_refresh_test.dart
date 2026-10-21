import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/wrf_forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/wrf_forecast_provider.dart';

import '../../test_helpers/fakes.dart';
import 'wrf_forecast_unavailable_test.dart' show serverForecast;

final _initial = CoarseLocation.round(44.98765, -93.26543);
final _moved = CoarseLocation.round(40.71278, -74.00594);

class _Resolver extends WeatherLocationResolver {
  WeatherLocationResult answer = WeatherLocationResult.located(_moved);
  Completer<WeatherLocationResult>? pending;
  int calls = 0;

  @override
  Future<WeatherLocationResult> resolve() async {
    calls++;
    return pending?.future ?? answer;
  }
}

class _Repository extends FakeWeatherRepository {
  final requests = <CoarseLocation>[];
  Completer<Either<Failure, WrfForecastModel>>? pending;

  @override
  Future<Either<Failure, WrfForecastModel>> getWrfForecast(
    CoarseLocation location,
  ) async {
    requests.add(location);
    return pending?.future ?? Right(serverForecast());
  }
}

ProviderContainer _container(_Resolver resolver, _Repository repository) {
  final c = ProviderContainer(
    overrides: [
      weatherLocationResolverProvider.overrideWithValue(resolver),
      weatherRepositoryProvider.overrideWithValue(repository),
    ],
  );
  c.listen(wrfForecastProvider, (_, _) {});
  return c;
}

void main() {
  for (final reason in [
    LocationUnavailableReason.permissionDenied,
    LocationUnavailableReason.servicesOff,
  ]) {
    testWidgets('timer stops without a request when ${reason.name}', (
      tester,
    ) async {
      final resolver = _Resolver();
      final repository = _Repository();
      final c = _container(resolver, repository);
      addTearDown(c.dispose);
      await c.read(wrfForecastProvider.notifier).loadWrfForecast(_initial);
      resolver.answer = WeatherLocationResult.unavailable(reason);
      await tester.pump(const Duration(minutes: 5));
      await tester.pump();
      expect(resolver.calls, 1);
      expect(repository.requests, [_initial]);
      expect(c.read(wrfForecastProvider).data, isNull);
      expect(c.read(wrfForecastProvider).unavailable, isTrue);
      expect(c.read(wrfForecastProvider).loading, isFalse);
      await tester.pump(const Duration(minutes: 10));
      expect(resolver.calls, 1, reason: 'blocked refresh is not a retry loop');
      expect(repository.requests, [_initial]);
      c.dispose();
    });
  }

  testWidgets('timer fetches the newly resolved rounded cell', (tester) async {
    final resolver = _Resolver();
    final repository = _Repository();
    final c = _container(resolver, repository);
    addTearDown(c.dispose);
    await c.read(wrfForecastProvider.notifier).loadWrfForecast(_initial);
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(resolver.calls, 1);
    expect(repository.requests, [_initial, _moved]);
    expect(c.read(wrfForecastProvider).data, isNotNull);
    c.dispose();
  });

  testWidgets('one pending HTTP refresh spans multiple timer ticks', (
    tester,
  ) async {
    final resolver = _Resolver();
    final repository = _Repository();
    final c = _container(resolver, repository);
    addTearDown(c.dispose);
    await c.read(wrfForecastProvider.notifier).loadWrfForecast(_initial);
    final pending = Completer<Either<Failure, WrfForecastModel>>();
    repository.pending = pending;
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    expect(resolver.calls, 1);
    expect(repository.requests, [_initial, _moved]);
    pending.complete(Right(serverForecast()));
    await tester.pump();
    await tester.pump();
    expect(repository.requests, [_initial, _moved]);
    c.dispose();
  });

  testWidgets('new load prevents an old HTTP response overwriting it', (
    tester,
  ) async {
    final resolver = _Resolver();
    final old = Completer<Either<Failure, WrfForecastModel>>();
    final repository = _Repository()..pending = old;
    final c = _container(resolver, repository);
    addTearDown(c.dispose);
    final notifier = c.read(wrfForecastProvider.notifier);
    final first = notifier.loadWrfForecast(_initial);
    repository.pending = null;
    await notifier.loadWrfForecast(_moved);
    old.complete(Right(serverForecast(tempC: 99)));
    await first;
    expect(c.read(wrfForecastProvider).data!.hourly.single.temperatureC, 27.25);
    c.dispose();
  });

  testWidgets('dispose cancels timer and ignores an outstanding HTTP answer', (
    tester,
  ) async {
    final resolver = _Resolver();
    final pending = Completer<Either<Failure, WrfForecastModel>>();
    final repository = _Repository()..pending = pending;
    final c = _container(resolver, repository);
    final load = c.read(wrfForecastProvider.notifier).loadWrfForecast(_initial);
    c.dispose();
    pending.complete(Right(serverForecast()));
    await expectLater(load, completes);
    await tester.pump(const Duration(minutes: 10));
    expect(repository.requests, [_initial]);
    expect(resolver.calls, 0);
  });

  testWidgets('a newer manual load cancels an older location resolution', (
    tester,
  ) async {
    final resolver = _Resolver()..pending = Completer();
    final repository = _Repository();
    final c = _container(resolver, repository);
    addTearDown(c.dispose);
    final notifier = c.read(wrfForecastProvider.notifier);
    await notifier.loadWrfForecast(_initial);
    await tester.pump(const Duration(minutes: 5));
    await notifier.loadWrfForecast(_initial);
    resolver.pending!.complete(WeatherLocationResult.located(_moved));
    await tester.pump();
    expect(repository.requests, [_initial, _initial]);
    c.dispose();
  });
}
