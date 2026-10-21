import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/core/widgets/app_error_widget.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/forecast_detail_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_detail_screen.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/location_needed_card.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/weather_card.dart';

/// mobile#270: the forecast detail screen is built from the route the
/// backend really mounts, `GET /api/weather/forecast/:location`
/// (backend server/routes/weather-routes.js:173 → enhanced-weather-controller
/// getWeatherForecast → noaa-nws-api-service getForecast/getHourlyForecast).
///
/// - `?type=hourly&days=1`: 24 NOAA hourly periods, each with
///   `relativeHumidity` and `probabilityOfPrecipitation` quantities.
/// - `?days=14`: 14 NOAA day/night periods (7 days), with no humidity,
///   no pressure and no precipitation chance.
///
/// Pressure is never in either response. Nothing absent is shown as a value.
///
/// Driven through the real [WeatherRepository] over a recording HTTP adapter
/// and the real Geolocator method channel, so it runs unchanged against the
/// pre-fix app (which requested the never-mounted `/detail` path).

const _geolocator = MethodChannel('flutter.baseflow.com/geolocator');

const _forecastPath = '/api/weather/forecast/45.0,-93.3';

Map<String, dynamic> _envelope(List<Map<String, dynamic>> periods) => {
  'location': {'latitude': 45.0, 'longitude': -93.3, 'name': '45.0,-93.3'},
  'forecast': {'periods': periods},
  'source': 'NOAA-NWS',
  'timestamp': '2026-09-28T17:00:00.000Z',
  'status': 'success',
};

Map<String, dynamic> _quantity(String unit, num? value) => {
  'unitCode': 'wmoUnit:$unit',
  'value': value,
};

/// The backend's `?type=hourly` shape (noaa-nws-api-service.js:310-324).
Map<String, dynamic> hourlyEnvelope() => _envelope([
  {
    'number': 1,
    'startTime': '2026-09-28T18:00:00-05:00',
    'endTime': '2026-09-28T19:00:00-05:00',
    'isDaytime': false,
    'temperature': 68,
    'temperatureUnit': 'F',
    'probabilityOfPrecipitation': _quantity('percent', 20),
    'dewpoint': _quantity('degC', 12.2),
    'relativeHumidity': _quantity('percent', 62),
    'windSpeed': '10 mph',
    'windDirection': 'NW',
    'shortForecast': 'Mostly Clear',
  },
  {
    'number': 2,
    'startTime': '2026-09-28T19:00:00-05:00',
    'endTime': '2026-09-28T20:00:00-05:00',
    'isDaytime': false,
    'temperature': 66,
    'temperatureUnit': 'F',
    'probabilityOfPrecipitation': _quantity('percent', null),
    'dewpoint': _quantity('degC', 12.0),
    'relativeHumidity': _quantity('percent', null),
    'windSpeed': '5 mph',
    'windDirection': 'N',
    'shortForecast': 'Clear',
  },
]);

/// The backend's daily shape (noaa-nws-api-service.js:258-272): 14 day and
/// night periods starting with "Tonight" on Mon 2026-09-28.
Map<String, dynamic> dailyEnvelope() {
  String stamp(DateTime day, int hour) =>
      '${day.toIso8601String().substring(0, 10)}T${hour.toString().padLeft(2, '0')}:00:00-05:00';
  final first = DateTime.utc(2026, 9, 28);
  final periods = <Map<String, dynamic>>[
    {
      'number': 1,
      'name': 'Tonight',
      'startTime': stamp(first, 18),
      'isDaytime': false,
      'temperature': 58,
      'temperatureUnit': 'F',
      'windSpeed': '5 to 10 mph',
      'windDirection': 'NW',
      'shortForecast': 'Clear',
    },
  ];
  for (var k = 1; periods.length < 14; k++) {
    final day = first.add(Duration(days: k));
    periods.add({
      'number': periods.length + 1,
      'name': 'Day $k',
      'startTime': stamp(day, 6),
      'isDaytime': true,
      'temperature': 75,
      'temperatureUnit': 'F',
      'windSpeed': '10 to 15 mph',
      'windDirection': 'S',
      'shortForecast': 'Sunny',
    });
    if (periods.length == 14) break;
    periods.add({
      'number': periods.length + 1,
      'name': 'Day $k Night',
      'startTime': stamp(day, 18),
      'isDaytime': false,
      'temperature': 57,
      'temperatureUnit': 'F',
      'windSpeed': '5 mph',
      'windDirection': 'S',
      'shortForecast': 'Mostly Clear',
    });
  }
  return _envelope(periods);
}

/// Records every request. Answers the forecast route by its `type` query;
/// anything else is the backend's catch-all 404.
class _Backend implements HttpClientAdapter {
  Object? hourlyBody = hourlyEnvelope();
  int hourlyStatus = 200;
  Object? dailyBody = dailyEnvelope();
  int dailyStatus = 200;

  /// When set, forecast responses wait for it.
  Completer<void>? gate;

  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    requests.add(uri);
    Object? body;
    int status;
    if (uri.path == _forecastPath) {
      await gate?.future;
      final hourly = uri.queryParameters['type'] == 'hourly';
      body = hourly ? hourlyBody : dailyBody;
      status = hourly ? hourlyStatus : dailyStatus;
    } else {
      await gate?.future;
      status = 404;
      body = {
        'success': false,
        'error': {'code': 'REQUEST_ERROR', 'message': 'Endpoint not found'},
      };
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Granted permission and a fix at 45.0,-93.3 unless [permission] changes.
class _Device {
  /// 0 denied, 2 whileInUse.
  int permission = 2;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'checkPermission':
        return permission;
      case 'isLocationServiceEnabled':
        return true;
      case 'getCurrentPosition':
        return <String, Object?>{
          'latitude': 44.98765,
          'longitude': -93.26543,
          'timestamp': DateTime.utc(2026, 9, 28).millisecondsSinceEpoch,
          'accuracy': 25.0,
          'altitude': 0.0,
          'heading': 0.0,
          'speed': 0.0,
          'speed_accuracy': 0.0,
        };
    }
    return null;
  }
}

class _MetricPreferences extends AppPreferencesNotifier {
  @override
  AppPreferencesState build() => const AppPreferencesState();
}

Future<ProviderContainer> _pumpDetail(
  WidgetTester tester, {
  required _Backend backend,
  _Device? device,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final phone = device ?? _Device();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_geolocator, phone.handle);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocator, null),
  );
  final dio = Dio(BaseOptions(baseUrl: 'https://tailnet.test:9444/api'))
    ..httpClientAdapter = backend;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weatherRepositoryProvider.overrideWithValue(WeatherRepository(dio)),
        appPreferencesProvider.overrideWith(_MetricPreferences.new),
      ],
      child: const MaterialApp(home: ForecastDetailScreen()),
    ),
  );
  await _settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openDailyTab(WidgetTester tester) async {
  await tester.tap(find.text('7-Day'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('requests only the mounted forecast route, never /detail', (
    tester,
  ) async {
    final backend = _Backend();
    await _pumpDetail(tester, backend: backend);

    expect(backend.requests, hasLength(2));
    for (final uri in backend.requests) {
      expect(uri.path, _forecastPath);
      expect(uri.path, isNot(endsWith('/detail')));
    }
    expect(backend.requests.map((u) => u.queryParameters).toSet(), {
      {'type': 'hourly', 'days': '1'},
      {'days': '14'},
    });
  });

  testWidgets('Hourly: NOAA hourly periods with their real humidity', (
    tester,
  ) async {
    await _pumpDetail(tester, backend: _Backend());

    expect(find.byType(AppErrorWidget), findsNothing);
    expect(find.text('20°C'), findsOneWidget, reason: '68 °F');
    expect(find.textContaining('Humidity 62%'), findsOneWidget);
    expect(find.textContaining('16 km/h'), findsOneWidget, reason: '10 mph');
    expect(find.textContaining('Mostly Clear'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget, reason: 'precipitation chance');
    // The second hour has no humidity and no precipitation chance: shown as
    // absent, never as 0.
    expect(find.textContaining('Humidity —'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.textContaining('Humidity 0%'), findsNothing);
  });

  for (final (label, status, body) in [
    ('500', 500, {'error': true, 'message': 'Failed'}),
    ('no periods', 200, _envelope(const [])),
  ]) {
    testWidgets('hourly $label: "not available yet", 7-day still shown', (
      tester,
    ) async {
      final backend = _Backend()
        ..hourlyStatus = status
        ..hourlyBody = body;
      await _pumpDetail(tester, backend: backend);

      expect(find.text('Hourly forecast not available yet'), findsOneWidget);
      expect(find.byType(AppErrorWidget), findsNothing);
      expect(find.textContaining('Something went wrong'), findsNothing);

      await _openDailyTab(tester);
      expect(find.text('24°C'), findsWidgets);
    });
  }

  testWidgets('7-Day: day/night periods grouped into 7 days, no invented '
      'humidity', (tester) async {
    await _pumpDetail(tester, backend: _Backend());
    await _openDailyTab(tester);

    // Mon 28 has only "Tonight" (a low); Tue 29 – Sun 4 have high and low;
    // Mon 5's lone day period is past 7 days.
    expect(find.text('Sun, Oct 4'), findsOneWidget);
    expect(find.text('Mon, Oct 5'), findsNothing);
    expect(find.text('24°C'), findsNWidgets(6), reason: 'highs of 75 °F');
    expect(find.text('14°C'), findsNWidgets(7), reason: 'lows of 57/58 °F');
    // Daily periods without humidity hide the row: never a number, never "—".
    expect(find.textContaining('Humidity'), findsNothing);
    expect(find.textContaining('Humidity 0%'), findsNothing);
    expect(find.textContaining('Something went wrong'), findsNothing);
  });

  testWidgets('both requests fail: the error, with retry', (tester) async {
    final backend = _Backend()
      ..hourlyStatus = 500
      ..dailyStatus = 500
      ..hourlyBody = {'error': true}
      ..dailyBody = {'error': true};
    await _pumpDetail(tester, backend: backend);

    expect(find.byType(AppErrorWidget), findsOneWidget);
  });

  // mobile#326 item 1 (reviewer probe J): a result from a load that began
  // before permission was revoked must not replace the no-location state.
  testWidgets('probe J: a late answer after revoke keeps "Allow location"', (
    tester,
  ) async {
    final device = _Device();
    final backend = _Backend()..gate = Completer<void>();
    final container = await _pumpDetail(
      tester,
      backend: backend,
      device: device,
    );
    // Keep the autoDispose provider alive across the steps.
    final sub = container.listen(forecastDetailProvider, (_, _) {});
    addTearDown(sub.close);
    expect(backend.requests, isNotEmpty, reason: 'load A in flight');
    final sent = backend.requests.length;

    device.permission = 0;
    await container.read(forecastDetailProvider.notifier).loadLocal();
    await _settle(tester);
    expect(container.read(forecastDetailProvider).locationNeeded, isTrue);

    backend.gate!.complete();
    await _settle(tester);

    final state = container.read(forecastDetailProvider);
    expect(state.locationNeeded, isTrue);
    expect(state.error, isNull);
    expect(state.detail, isNull);
    expect(backend.requests, hasLength(sent), reason: 'no new request');
    expect(
      find.text('Allow location to see your local forecast'),
      findsOneWidget,
    );
  });

  test('ForecastDetailState.copyWith keeps locationNeeded', () {
    const state = ForecastDetailState(
      locationUnavailable: LocationUnavailableReason.permissionDenied,
    );
    expect(state.copyWith(loading: false).locationNeeded, isTrue);
  });

  test('ForecastDetailState.copyWith clears locationNeeded when told to', () {
    const state = ForecastDetailState(
      locationUnavailable: LocationUnavailableReason.permissionDenied,
    );
    expect(
      state.copyWith(clearLocationUnavailable: true).locationNeeded,
      isFalse,
    );
  });

  // Review round 1 P1 (#330): copyWith always re-forwarded the current
  // locationNeeded, so a load that starts after a later grant stayed stuck
  // behind "Allow location" forever, even after a real success or failure.
  group('review round 1 P1: locationNeeded clears after a later grant', () {
    testWidgets('denial, then grant, then a successful load shows the detail', (
      tester,
    ) async {
      final device = _Device()..permission = 0;
      final backend = _Backend();
      final container = await _pumpDetail(
        tester,
        backend: backend,
        device: device,
      );
      final sub = container.listen(forecastDetailProvider, (_, _) {});
      addTearDown(sub.close);
      expect(container.read(forecastDetailProvider).locationNeeded, isTrue);
      expect(backend.requests, isEmpty);
      expect(find.byType(LocationNeededCard), findsOneWidget);

      device.permission = 2;
      // unawaited + _settle: a directly-awaited notifier call that fires
      // real HTTP requests can hang here (the test zone's fake clock only
      // advances inside pump); the existing reconnect-refresh test uses
      // the same pattern (weather_local_location_test.dart).
      unawaited(container.read(forecastDetailProvider.notifier).loadLocal());
      await _settle(tester);

      final state = container.read(forecastDetailProvider);
      expect(state.locationNeeded, isFalse);
      expect(state.detail, isNotNull);
      expect(state.error, isNull);
      expect(find.byType(LocationNeededCard), findsNothing);
    });

    testWidgets(
      'denial, then grant, then a failed load shows error and Retry',
      (tester) async {
        final device = _Device()..permission = 0;
        final backend = _Backend()
          ..hourlyStatus = 500
          ..dailyStatus = 500
          ..hourlyBody = {'error': true}
          ..dailyBody = {'error': true};
        final container = await _pumpDetail(
          tester,
          backend: backend,
          device: device,
        );
        final sub = container.listen(forecastDetailProvider, (_, _) {});
        addTearDown(sub.close);
        expect(container.read(forecastDetailProvider).locationNeeded, isTrue);

        device.permission = 2;
        unawaited(container.read(forecastDetailProvider.notifier).loadLocal());
        await _settle(tester);

        final state = container.read(forecastDetailProvider);
        expect(state.locationNeeded, isFalse);
        expect(state.detail, isNull);
        expect(state.error, isNotNull);
        expect(find.byType(LocationNeededCard), findsNothing);
        expect(find.byType(AppErrorWidget), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      },
    );
  });

  group('dashboard card: fields the daily forecast never carries', () {
    Future<void> pumpCard(WidgetTester tester, ForecastModel forecast) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferencesProvider.overrideWith(_MetricPreferences.new),
          ],
          child: MaterialApp(
            home: Scaffold(body: WeatherCard(forecast: forecast)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('humidity and pressure say "Not available", never 0', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const ForecastModel(
          temperature: 24,
          windSpeed: 21,
          location: 'Your area',
          timestamp: '2026-09-28T18:00:00-05:00',
        ),
      );

      expect(find.text('24°C'), findsOneWidget);
      expect(find.text('21 km/h'), findsOneWidget);
      expect(find.text('Not available'), findsNWidgets(2));
      expect(find.text('0%'), findsNothing);
      expect(find.textContaining('0 hPa'), findsNothing);
    });

    testWidgets('control: real humidity and pressure are shown', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const ForecastModel(
          temperature: 24,
          humidity: 62,
          pressure: 1012,
          windSpeed: 21,
          location: 'Your area',
          timestamp: '2026-09-28T18:00:00-05:00',
        ),
      );

      expect(find.text('62%'), findsOneWidget);
      expect(find.text('Not available'), findsNothing);
    });
  });
}
