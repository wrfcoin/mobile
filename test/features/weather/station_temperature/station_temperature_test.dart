// mobile#299 (mobile half; backend is wrfcoin/backend#1382): heat-wave,
// cold-snap, first-frost, warmer-than-yesterday and 7-day-range narratives
// from the 0.1 degree cell's station temperature history.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/weather/data/station_temperature_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/station_temperature.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/station_temperature_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/station_temperature_section.dart';

import '../../../test_helpers/fakes.dart';
import 'temperature_test_completion.dart';

final _now = DateTime.utc(2026, 10, 1, 15);

Map<String, dynamic> _day(String date, double? min, double? max, double? mean, [int samples = 5]) => {
  'date': date,
  'minC': min,
  'maxC': max,
  'meanC': mean,
  'samples': min == null ? 0 : samples,
};

Map<String, dynamic> _body(List<Map<String, dynamic>> daily, {String? bucket}) => {
  'cell': {'latE1': 450, 'lonE1': -933},
  'days': 14,
  'window': {'from': '2026-09-18', 'to': '2026-10-01'},
  'hours': [],
  'daily': daily,
  'contributorBucket': ?bucket,
  'truncated': false,
};

StationTemperatureHistory _history(List<Map<String, dynamic>> daily) =>
    StationTemperatureHistory.fromJson(_body(daily));

List<String> _titles(List<dynamic> narratives) => narratives.map<String>((n) => n.title as String).toList();

void main() {
  group('CoarseLocation cell ints', () {
    test('latE1/lonE1 are the 0.1 degree cell in integer tenths', () {
      final c = CoarseLocation.round(44.98, -93.27);
      expect(c.latE1, 450);
      expect(c.lonE1, -933);
      expect(CoarseLocation.round(-0.04, 0.04).latE1, 0);
    });
  });

  group('narratives from station data', () {
    test('yesterday warmer than the day before by X (completed days only)', () {
      final n = buildStationTemperatureNarratives(
        _history([_day('2026-09-29', 10, 16, 12.0), _day('2026-09-30', 12, 19, 14.36)]),
        _now,
      );
      expect(_titles(n), contains('Yesterday was warmer than the day before by 2.4°C'));
    });

    test('cooler than the day before, and about the same when the difference rounds to 0.0', () {
      var n = buildStationTemperatureNarratives(
        _history([_day('2026-09-29', 10, 16, 14.0), _day('2026-09-30', 9, 14, 11.5)]),
        _now,
      );
      expect(_titles(n), contains('Yesterday was cooler than the day before by 2.5°C'));
      n = buildStationTemperatureNarratives(
        _history([_day('2026-09-29', 10, 16, 14.0), _day('2026-09-30', 9, 14, 14.03)]),
        _now,
      );
      expect(_titles(n), contains('Yesterday was about the same as the day before'));
    });

    test('today has no row: yesterday against the day before', () {
      final n = buildStationTemperatureNarratives(
        _history([_day('2026-09-29', 8, 12, 10.0), _day('2026-09-30', 10, 16, 13.0), _day('2026-10-01', null, null, null)]),
        _now,
      );
      expect(_titles(n), contains('Yesterday was warmer than the day before by 3.0°C'));
    });

    test('no comparison when the two days are not adjacent (a null day in between is never bridged)', () {
      final n = buildStationTemperatureNarratives(
        _history([_day('2026-09-29', 8, 12, 10.0), _day('2026-09-30', null, null, null), _day('2026-10-01', 12, 19, 14.0)]),
        _now,
      );
      expect(_titles(n).where((t) => t.toLowerCase().contains('than')), isEmpty);
    });

    test('7-day range spans min of minC to max of maxC over the last 7 UTC days only', () {
      final n = buildStationTemperatureNarratives(
        _history([
          _day('2026-09-20', -8, 2, -3.0), // outside the 7 days ending 2026-10-01
          _day('2026-09-26', 5.5, 15, 10.0),
          _day('2026-09-28', 3.25, 21.75, 12.0),
          _day('2026-10-01', 6, 18, 12.0), // today: partial, ignored
        ]),
        _now,
      );
      expect(_titles(n), contains('Past 7 days: 3.3°C to 21.8°C'));
    });

    test('7 completed days means yesterday back to today-7 (offsets 1..7), not today back to today-6', () {
      final n = buildStationTemperatureNarratives(
        _history([
          _day('2026-09-24', -10, 40, 15.0), // today-7: the seventh completed day, included
          _day('2026-09-29', 10, 20, 15.0),
          _day('2026-09-30', 10, 20, 15.0),
        ]),
        _now,
      );
      expect(_titles(n), contains('Past 7 days: -10.0°C to 40.0°C'));
      final older = buildStationTemperatureNarratives(
        _history([_day('2026-09-23', -10, 40, 15.0), _day('2026-09-29', 10, 20, 15.0), _day('2026-09-30', 10, 20, 15.0)]),
        _now,
      );
      expect(_titles(older), contains('Past 7 days: 10.0°C to 20.0°C')); // today-8 is outside
    });

    test('a partial-today row never drives the comparison, the range, frost or provenance', () {
      final n = buildStationTemperatureNarratives(
        _history([
          _day('2026-09-29', 10, 16, 12.0),
          _day('2026-09-30', 12, 19, 14.0),
          _day('2026-10-01', -20, 50, 99.0), // today: partial
          _day('2026-10-02', -20, 50, 99.0), // future: never valid
        ]),
        _now,
      );
      expect(_titles(n), ['Yesterday was warmer than the day before by 2.0°C', 'Past 7 days: 10.0°C to 19.0°C']);
      expect(n.first.provenance!.observedTo, DateTime.utc(2026, 9, 30));
      expect(n.first.provenance!.observationCount, 2);
    });

    test('heat wave: 3 consecutive days with max >= 35; a null day breaks the run', () {
      final hot = [_day('2026-09-28', 20, 36, 28.0), _day('2026-09-29', 21, 35, 28.0), _day('2026-09-30', 22, 37, 29.0)];
      expect(_titles(buildStationTemperatureNarratives(_history(hot), _now)), contains('Heat wave nearby'));
      final broken = [hot[0], _day('2026-09-29', null, null, null), hot[2]];
      expect(_titles(buildStationTemperatureNarratives(_history(broken), _now)), isNot(contains('Heat wave nearby')));
      final two = [hot[1], hot[2]];
      expect(_titles(buildStationTemperatureNarratives(_history(two), _now)), isNot(contains('Heat wave nearby')));
    });

    test('heat wave: a day missing from the list (not just null) breaks the run', () {
      final gap = [_day('2026-09-28', 20, 36, 28.0), _day('2026-09-30', 22, 37, 29.0), _day('2026-10-01', 22, 38, 29.0)];
      expect(_titles(buildStationTemperatureNarratives(_history(gap), _now)), isNot(contains('Heat wave nearby')));
    });

    test('cold snap: 3 consecutive days with min <= -5', () {
      final cold = [_day('2026-09-28', -6, 0, -3.0), _day('2026-09-29', -5, 1, -2.0), _day('2026-09-30', -7, -1, -4.0)];
      expect(_titles(buildStationTemperatureNarratives(_history(cold), _now)), contains('Cold snap nearby'));
      expect(
        _titles(buildStationTemperatureNarratives(_history([cold[0], cold[1]]), _now)),
        isNot(contains('Cold snap nearby')),
      );
    });

    test('frost: the most recent day with min <= 0 is reported with its lowest value', () {
      final n = buildStationTemperatureNarratives(
        _history([_day('2026-09-27', -1.5, 8, 3.0), _day('2026-09-30', -0.25, 9, 4.0), _day('2026-10-01', 2, 10, 6.0)]),
        _now,
      );
      final frost = n.firstWhere((x) => x.title == 'Frost nearby');
      expect(frost.description, contains('-0.3°C'));
      expect(frost.description, contains('2026-09-30'));
    });

    test('no frost, heat or cold events for mild weather', () {
      final n = buildStationTemperatureNarratives(
        _history([_day('2026-09-30', 10, 16, 12.0), _day('2026-10-01', 11, 17, 13.0)]),
        _now,
      );
      expect(_titles(n).where((t) => t.contains('nearby') && !t.startsWith('Past')), isEmpty);
    });

    test('empty and all-null histories produce no narratives (nothing is invented)', () {
      expect(buildStationTemperatureNarratives(_history([]), _now), isEmpty);
      expect(
        buildStationTemperatureNarratives(
          _history([_day('2026-09-30', null, null, null), _day('2026-10-01', null, null, null)]),
          _now,
        ),
        isEmpty,
      );
      expect(_history([_day('2026-09-30', null, null, null)]).hasData, isFalse);
    });

    test('provenance names the station source and the window; it is shareable', () {
      final n = buildStationTemperatureNarratives(
        _history([_day('2026-09-30', 10, 16, 12.0), _day('2026-10-01', 12, 19, 14.0)]),
        _now,
      );
      expect(n.first.provenance!.source, 'station:temperature-history');
      expect(n.first.isShareable, isTrue);
    });

    test('no sampleCount, no per-day samples and no contributor bucket: narratives are the same', () {
      Map<String, dynamic> bare(String d, double mn, double mx, double me) => {'date': d, 'minC': mn, 'maxC': mx, 'meanC': me};
      final h = StationTemperatureHistory.fromJson({
        'daily': [bare('2026-09-29', 10, 16, 12.0), bare('2026-09-30', 12, 19, 14.36)],
      });
      final n = buildStationTemperatureNarratives(h, _now);
      expect(_titles(n), contains('Yesterday was warmer than the day before by 2.4°C'));
      expect(n.first.provenance!.observationCount, 2); // days with data, not samples
    });

    test('a bogus or huge sampleCount or samples value changes nothing', () {
      final h = StationTemperatureHistory.fromJson({
        'sampleCount': 'many',
        'daily': [
          {'date': '2026-09-29', 'minC': 10, 'maxC': 16, 'meanC': 12.0, 'samples': -1},
          {'date': '2026-09-30', 'minC': 12, 'maxC': 19, 'meanC': 14.0, 'samples': 'x'},
        ],
      });
      expect(_titles(buildStationTemperatureNarratives(h, _now)), contains('Yesterday was warmer than the day before by 2.0°C'));
    });

    test('only a today row (no completed day): nothing is said', () {
      expect(buildStationTemperatureNarratives(_history([_day('2026-10-01', 12, 19, 14.0)]), _now), isEmpty);
    });

    test('malformed rows are ignored, never turned into numbers', () {
      final h = StationTemperatureHistory.fromJson({
        'daily': [
          {'date': 'not-a-date', 'minC': 1, 'maxC': 2, 'meanC': 1.5, 'samples': 3},
          {'date': '2026-10-01', 'minC': 'hot', 'maxC': null, 'meanC': 12.0, 'samples': 3},
          'junk',
        ],
      });
      expect(h.daily.length, 1);
      expect(h.daily.single.minC, isNull);
    });
  });

  group('data source', () {
    Dio dioWith(Response<dynamic> Function(RequestOptions) answer, List<Uri> seen) {
      final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            seen.add(o.uri);
            final r = answer(o);
            if ((r.statusCode ?? 200) >= 400) {
              h.reject(DioException(requestOptions: o, type: DioExceptionType.badResponse, response: r));
            } else {
              h.resolve(r);
            }
          },
        ),
      );
      return dio;
    }

    final cell = CoarseLocation.round(44.98, -93.27);

    test('requests the integer tenths cell only: latE1, lonE1, days and nothing finer', () async {
      final seen = <Uri>[];
      final ds = StationTemperatureRemoteDataSource(
        dioWith((o) => Response(requestOptions: o, statusCode: 200, data: _body([])), seen),
      );
      final r = await ds.fetch(cell);
      expect(r.kind, StationTemperatureFetchKind.data);
      expect(seen.single.path, '/weather/temperature-history');
      expect(seen.single.queryParameters, {'latE1': '450', 'lonE1': '-933', 'days': '14'});
      expect(seen.single.toString(), isNot(contains('44.98')));
    });

    test('401, 403, 404 and 501 are a quiet hide; 503, 429, 500 and a network error are unavailable', () async {
      for (final code in [401, 403, 404, 501]) {
        final ds = StationTemperatureRemoteDataSource(
          dioWith((o) => Response(requestOptions: o, statusCode: code, data: {'error': 'x'}), []),
        );
        expect((await ds.fetch(cell)).kind, StationTemperatureFetchKind.hidden, reason: '$code');
      }
      for (final code in [429, 500, 503]) {
        final ds = StationTemperatureRemoteDataSource(
          dioWith((o) => Response(requestOptions: o, statusCode: code, data: {'error': 'x'}), []),
        );
        expect((await ds.fetch(cell)).kind, StationTemperatureFetchKind.unavailable, reason: '$code');
      }
      final failing = Dio(BaseOptions(baseUrl: 'http://backend.test'))
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError))));
      expect((await StationTemperatureRemoteDataSource(failing).fetch(cell)).kind, StationTemperatureFetchKind.unavailable);
    });

    test('a non-JSON-object 200 is unavailable, not data', () async {
      final ds = StationTemperatureRemoteDataSource(dioWith((o) => Response(requestOptions: o, statusCode: 200, data: 'oops'), []));
      expect((await ds.fetch(cell)).kind, StationTemperatureFetchKind.unavailable);
    });
  });

  group('provider', () {
    late List<Uri> seen;
    Future<ProviderContainer> make({
      bool signedIn = true,
      CoarseLocation? location,
      bool foreground = true,
      int status = 200,
      Map<String, dynamic>? body,
    }) async {
      seen = [];
      final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) async {
              seen.add(o.uri);
              // Synthetic asynchronous response: completion must not depend on
              // the test runner finishing within a fixed 20 ms window.
              await Future<void>.delayed(const Duration(milliseconds: 100));
              final r = Response<dynamic>(requestOptions: o, statusCode: status, data: body ?? _body([_day('2026-09-30', 10, 16, 12.0), _day('2026-10-01', 12, 19, 14.0)]));
              status >= 400 ? h.reject(DioException(requestOptions: o, type: DioExceptionType.badResponse, response: r)) : h.resolve(r);
            },
          ),
        );
      final container = ProviderContainer(
        overrides: [
          stationTemperatureProvider.overrideWith(TrackedTemperatureNotifier.new),
          stationTemperatureDataSourceProvider.overrideWithValue(StationTemperatureRemoteDataSource(dio)),
          weatherLocationResolverProvider.overrideWithValue(FixedWeatherLocationResolver(location ?? CoarseLocation.round(44.98, -93.27))),
          stationTemperatureSignedInProvider.overrideWithValue(() async => signedIn),
          stationTemperatureForegroundProvider.overrideWithValue(() => foreground),
          weatherNarrativesClockProvider.overrideWithValue(() => _now),
        ],
      );
      addTearDown(container.dispose);
      container.listen(stationTemperatureProvider, (_, _) {});
      await temperatureLoad(container);
      return container;
    }

    test('signed in, foreground, located: fetches the cell and produces narratives', () async {
      final c = await make();
      final s = c.read(stationTemperatureProvider);
      expect(s.status, StationTemperatureStatus.ready);
      expect(s.narratives, isNotEmpty);
      expect(seen, hasLength(1));
    });

    test('not signed in: NO request and the section is hidden', () async {
      final c = await make(signedIn: false);
      expect(seen, isEmpty);
      expect(c.read(stationTemperatureProvider).status, StationTemperatureStatus.hidden);
    });

    test('backgrounded: NO request is made', () async {
      final c = await make(foreground: false);
      expect(seen, isEmpty);
      expect(c.read(stationTemperatureProvider).status, StationTemperatureStatus.hidden);
    });

    test('backgrounded: the location is not even resolved', () async {
      final resolver = _CountingResolver(CoarseLocation.round(44.98, -93.27));
      final c = ProviderContainer(overrides: [
          stationTemperatureProvider.overrideWith(TrackedTemperatureNotifier.new),
        stationTemperatureDataSourceProvider.overrideWithValue(StationTemperatureRemoteDataSource(Dio())),
        weatherLocationResolverProvider.overrideWithValue(resolver),
        stationTemperatureSignedInProvider.overrideWithValue(() async => true),
        stationTemperatureForegroundProvider.overrideWithValue(() => false),
      ]);
      addTearDown(c.dispose);
      c.listen(stationTemperatureProvider, (_, _) {});
      await temperatureLoad(c);
      expect(resolver.calls, 0);
    });

    test('backgrounded WHILE the location resolves: still no request', () async {
      var fg = true;
      seen = [];
      final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) => seen.add(o.uri)));
      final resolver = _CountingResolver(CoarseLocation.round(44.98, -93.27), onResolve: () => fg = false);
      final c = ProviderContainer(overrides: [
          stationTemperatureProvider.overrideWith(TrackedTemperatureNotifier.new),
        stationTemperatureDataSourceProvider.overrideWithValue(StationTemperatureRemoteDataSource(dio)),
        weatherLocationResolverProvider.overrideWithValue(resolver),
        stationTemperatureSignedInProvider.overrideWithValue(() async => true),
        stationTemperatureForegroundProvider.overrideWithValue(() => fg),
      ]);
      addTearDown(c.dispose);
      c.listen(stationTemperatureProvider, (_, _) {});
      await temperatureLoad(c);
      expect(resolver.calls, 1);
      expect(seen, isEmpty);
    });

    test('no location (permission denied): no request, hidden', () async {
      seen = [];
      final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) => seen.add(o.uri)));
      final container = ProviderContainer(
        overrides: [
          stationTemperatureProvider.overrideWith(TrackedTemperatureNotifier.new),
          stationTemperatureDataSourceProvider.overrideWithValue(StationTemperatureRemoteDataSource(dio)),
          weatherLocationResolverProvider.overrideWithValue(const FixedWeatherLocationResolver(null)),
          stationTemperatureSignedInProvider.overrideWithValue(() async => true),
          stationTemperatureForegroundProvider.overrideWithValue(() => true),
        ],
      );
      addTearDown(container.dispose);
      container.listen(stationTemperatureProvider, (_, _) {});
      await temperatureLoad(container);
      expect(seen, isEmpty);
      expect(container.read(stationTemperatureProvider).status, StationTemperatureStatus.hidden);
    });

    test('404 and 501 (backend not deployed yet) hide quietly; 503 is unavailable', () async {
      expect((await make(status: 404)).read(stationTemperatureProvider).status, StationTemperatureStatus.hidden);
      expect((await make(status: 501)).read(stationTemperatureProvider).status, StationTemperatureStatus.hidden);
      expect((await make(status: 503)).read(stationTemperatureProvider).status, StationTemperatureStatus.unavailable);
    });

    test('an empty cell is the empty state, not hidden and not fake numbers', () async {
      final c = await make(body: _body([], bucket: '0'));
      final s = c.read(stationTemperatureProvider);
      expect(s.status, StationTemperatureStatus.empty);
      expect(s.narratives, isEmpty);
    });

    test('refresh while backgrounded makes no further request', () async {
      var fg = true;
      seen = [];
      final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          seen.add(o.uri);
          h.resolve(Response(requestOptions: o, statusCode: 200, data: _body([_day('2026-10-01', 12, 19, 14.0)])));
        }));
      final c = ProviderContainer(overrides: [
          stationTemperatureProvider.overrideWith(TrackedTemperatureNotifier.new),
        stationTemperatureDataSourceProvider.overrideWithValue(StationTemperatureRemoteDataSource(dio)),
        weatherLocationResolverProvider.overrideWithValue(FixedWeatherLocationResolver(CoarseLocation.round(44.98, -93.27))),
        stationTemperatureSignedInProvider.overrideWithValue(() async => true),
        stationTemperatureForegroundProvider.overrideWithValue(() => fg),
        weatherNarrativesClockProvider.overrideWithValue(() => _now),
      ]);
      addTearDown(c.dispose);
      c.listen(stationTemperatureProvider, (_, _) {});
      await temperatureLoad(c);
      expect(seen, hasLength(1));
      fg = false;
      await c.read(stationTemperatureProvider.notifier).refresh();
      expect(seen, hasLength(1));
    });
  });

  group('section widget', () {
    Widget host(StationTemperatureState state) => ProviderScope(
      overrides: [stationTemperatureProvider.overrideWith(() => _FixedNotifier(state))],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: StationTemperatureSection()))),
    );

    testWidgets('ready: shows the station narratives', (tester) async {
      final narratives = buildStationTemperatureNarratives(
        _history([_day('2026-09-29', 10, 16, 12.0), _day('2026-09-30', 12, 19, 14.36)]),
        _now,
      );
      await tester.pumpWidget(host(StationTemperatureState(status: StationTemperatureStatus.ready, narratives: narratives)));
      expect(find.text('Yesterday was warmer than the day before by 2.4°C'), findsOneWidget);
      expect(find.textContaining('Past 7 days'), findsOneWidget);
    });

    testWidgets('empty: an honest no-data message, no numbers', (tester) async {
      await tester.pumpWidget(host(const StationTemperatureState(status: StationTemperatureStatus.empty)));
      expect(find.textContaining('No recent station temperature data'), findsOneWidget);
      expect(find.textContaining('°C'), findsNothing);
    });

    testWidgets('hidden: renders nothing at all', (tester) async {
      await tester.pumpWidget(host(const StationTemperatureState(status: StationTemperatureStatus.hidden)));
      expect(find.byType(Card), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('unavailable: a quiet note, not an error screen', (tester) async {
      await tester.pumpWidget(host(const StationTemperatureState(status: StationTemperatureStatus.unavailable)));
      expect(find.textContaining('unavailable'), findsOneWidget);
      expect(find.textContaining('Something Went Wrong'), findsNothing);
    });
  });
}

class _FixedNotifier extends StationTemperatureNotifier {
  _FixedNotifier(this._state);
  final StationTemperatureState _state;
  @override
  StationTemperatureState build() => _state;
}

class _CountingResolver extends FixedWeatherLocationResolver {
  _CountingResolver(super.location, {this.onResolve});
  final void Function()? onResolve;
  int calls = 0;
  @override
  Future<WeatherLocationResult> resolve() async {
    calls++;
    onResolve?.call();
    return super.resolve();
  }
}
