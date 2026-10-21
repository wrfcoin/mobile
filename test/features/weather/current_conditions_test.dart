import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_dashboard.dart';
import 'package:wrfcoin_mobile/services/offline/offline_data_buffer.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/fakes.dart';

/// (helpers copied from weather_location_access_test.dart)
/// mobile#327 and mobile#328: the Weather tab says *why* it has no location
/// and offers the action that fixes it. It asks for permission only on an
/// explicit tap, and it falls back to the last-known position when a fresh
/// fix times out.
///
/// Driven through the real Geolocator method channel and the real
/// [WeatherRepository] over a recording HTTP adapter, so the tests run
/// unchanged against the pre-fix app.

const _geolocator = MethodChannel('flutter.baseflow.com/geolocator');

/// Exact fix; rounded to 0.1° it is 45.0,-93.3.
const _fresh = (44.98765, -93.26543);

Map<String, Object?> _position((double, double) at) => {
  'latitude': at.$1,
  'longitude': at.$2,
  'timestamp': DateTime.utc(2026, 9, 28).millisecondsSinceEpoch,
  'accuracy': 25.0,
  'altitude': 0.0,
  'heading': 0.0,
  'speed': 0.0,
  'speed_accuracy': 0.0,
};

Map<String, dynamic> _forecastEnvelope({int temperature = 68}) => {
  'location': {'latitude': 45.0, 'longitude': -93.3, 'name': '45.0,-93.3'},
  'forecast': {
    'periods': [
      {
        'number': 1,
        'name': 'Tonight',
        'startTime': '2026-09-28T18:00:00-05:00',
        'isDaytime': false,
        'temperature': temperature,
        'temperatureUnit': 'F',
        'windSpeed': '5 to 10 mph',
        'windDirection': 'NW',
        'shortForecast': 'Clear',
      },
    ],
  },
  'source': 'NOAA-NWS',
  'timestamp': '2026-09-28T17:00:00.000Z',
  'status': 'success',
};

Map<String, dynamic> _alertsEnvelope() => {
  'alerts': <Object?>[],
  'count': 0,
  'source': 'NOAA-NWS',
  'timestamp': '2026-09-28T17:00:00.000Z',
  'status': 'success',
};

/// Records every request; answers forecast and alerts, and /current per
/// [currentBody] / [currentStatus].
class _RecordingBackend implements HttpClientAdapter {
  _RecordingBackend({
    this.currentBody,
    this.currentStatus = 200,
    this.currentHandler,
    this.forecastTemperature,
  });

  final Object? currentBody;
  final int currentStatus;

  /// Overrides [currentBody]/[currentStatus] per request: (status, body).
  final Future<(int, Object?)> Function(Uri uri)? currentHandler;

  /// Forecast temperature (°F) per request path; defaults to 68.
  final int Function(String path)? forecastTemperature;
  final requests = <Uri>[];

  List<String> get paths => requests.map((u) => u.path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    final path = options.uri.path;
    Object? body;
    var status = 200;
    if (path.startsWith('/api/weather/alerts/')) {
      body = _alertsEnvelope();
    } else if (path.startsWith('/api/weather/forecast/')) {
      body = _forecastEnvelope(
        temperature: forecastTemperature?.call(path) ?? 68,
      );
    } else if (path.startsWith('/api/weather/current/')) {
      final handler = currentHandler;
      if (handler != null) {
        (status, body) = await handler(options.uri);
      } else {
        body = currentBody ?? {'success': false};
        status = currentStatus;
      }
    } else {
      body = {'success': false};
      status = 404;
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

class _TestConnectivity extends Fake implements Connectivity {
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();

  Future<void> close() => _changes.close();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}

/// Geolocator platform state for one test: permission granted, fix arrives.
class _Device {
  _Device({required this.permission});

  /// The fix the platform reports; a test moves it to change location.
  (double, double) at = _fresh;

  /// 0 denied, 1 deniedForever, 2 whileInUse, 3 always.
  final int permission;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'checkPermission':
      case 'requestPermission':
        return permission;
      case 'isLocationServiceEnabled':
        return true;
      case 'getCurrentPosition':
      case 'getLastKnownPosition':
        return _position(at);
    }
    return null;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required _Device device,
  required _RecordingBackend backend,
  Widget home = const ForecastDashboard(),
}) async {
  final network = _TestConnectivity();
  addTearDown(network.close);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_geolocator, device.handle);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocator, null),
  );

  final db = createTestDatabase();
  addTearDown(db.close);
  final dio = Dio(BaseOptions(baseUrl: 'https://tailnet.test:9444/api'))
    ..httpClientAdapter = backend;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        offlineDataBufferProvider.overrideWithValue(
          OfflineDataBuffer(db: db, connectivity: network),
        ),
        weatherRepositoryProvider.overrideWithValue(WeatherRepository(dio)),
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
      child: MaterialApp(home: home),
    ),
  );
  await _settle(tester);
}

/// Lets real async work (database, HTTP adapter) and frames run.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, Object?> _current(Map<String, Object?> current) => {
  'location': {'latitude': 45.0, 'longitude': -93.3, 'name': '45.0,-93.3'},
  'current': current,
  'source': 'NOAA-NWS',
  'timestamp': '2026-09-29T17:00:00.000Z',
  'status': 'success',
};

Finder _row(String label, String value) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
  matching: find.text(value),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('requests /current at the 0.1° key, never the exact fix', (
    tester,
  ) async {
    final backend = _RecordingBackend(
      currentBody: _current({'relativeHumidityPercent': 68.2}),
    );
    await _pump(tester, device: _Device(permission: 2), backend: backend);

    expect(backend.paths, contains('/api/weather/current/45.0,-93.3'));
    // The existing calls are unchanged.
    expect(backend.paths, contains('/api/weather/forecast/45.0,-93.3'));
    expect(backend.paths, contains('/api/weather/alerts/45.0,-93.3'));
    for (final uri in backend.requests) {
      expect(uri.toString(), isNot(contains('44.98')));
      expect(uri.toString(), isNot(contains('93.26')));
    }
  });

  testWidgets('shows humidity and barometric pressure from /current', (
    tester,
  ) async {
    final backend = _RecordingBackend(
      currentBody: _current({
        'relativeHumidityPercent': 68.2,
        'barometricPressureHpa': 1009.82,
        'seaLevelPressureHpa': 1013.2,
      }),
    );
    await _pump(tester, device: _Device(permission: 2), backend: backend);

    expect(_row('Humidity', '68%'), findsOneWidget);
    expect(_row('Pressure', '1010 hPa'), findsOneWidget);
  });

  testWidgets('pressure falls back to sea-level when barometric is null', (
    tester,
  ) async {
    final backend = _RecordingBackend(
      currentBody: _current({
        'relativeHumidityPercent': 50,
        'barometricPressureHpa': null,
        'seaLevelPressureHpa': 1013.2,
      }),
    );
    await _pump(tester, device: _Device(permission: 2), backend: backend);

    expect(_row('Pressure', '1013 hPa'), findsOneWidget);
  });

  testWidgets('null humidity and pressure show "Not available"', (
    tester,
  ) async {
    final backend = _RecordingBackend(
      currentBody: _current({
        'relativeHumidityPercent': null,
        'barometricPressureHpa': null,
        'seaLevelPressureHpa': null,
      }),
    );
    await _pump(tester, device: _Device(permission: 2), backend: backend);

    expect(_row('Humidity', 'Not available'), findsOneWidget);
    expect(_row('Pressure', 'Not available'), findsOneWidget);
  });

  testWidgets('a real 0 humidity shows as 0%, not Not available', (
    tester,
  ) async {
    final backend = _RecordingBackend(
      currentBody: _current({
        'relativeHumidityPercent': 0,
        'barometricPressureHpa': 0,
      }),
    );
    await _pump(tester, device: _Device(permission: 2), backend: backend);

    expect(_row('Humidity', '0%'), findsOneWidget);
    expect(_row('Pressure', '0 hPa'), findsOneWidget);
  });

  testWidgets('a /current failure leaves the forecast card intact', (
    tester,
  ) async {
    final backend = _RecordingBackend(currentStatus: 500);
    await _pump(tester, device: _Device(permission: 2), backend: backend);

    expect(backend.paths, contains('/api/weather/current/45.0,-93.3'));
    // The forecast half still rendered: the card, and its temperature.
    expect(find.text('Current Conditions'), findsOneWidget);
    expect(find.text('20°C'), findsOneWidget);
    expect(_row('Humidity', 'Not available'), findsOneWidget);
    expect(_row('Pressure', 'Not available'), findsOneWidget);
  });

  /// Runs a fresh [WeatherNotifier.loadLocalWeather] on the pumped app.
  Future<void> reload(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ForecastDashboard)),
    );
    unawaited(container.read(weatherProvider.notifier).loadLocalWeather());
    await _settle(tester);
  }

  testWidgets('a location change never shows the old place\'s humidity', (
    tester,
  ) async {
    // Location A answers /current at once; B's /current stays pending.
    final pendingB = Completer<(int, Object?)>();
    final backend = _RecordingBackend(
      forecastTemperature: (path) => path.contains('45.0') ? 68 : 50,
      currentHandler: (uri) {
        if (uri.path.endsWith('45.0,-93.3')) {
          return Future.value((
            200,
            _current({
              'relativeHumidityPercent': 68,
              'barometricPressureHpa': 1010,
            }),
          ));
        }
        return pendingB.future;
      },
    );
    final device = _Device(permission: 2);
    await _pump(tester, device: device, backend: backend);
    expect(_row('Humidity', '68%'), findsOneWidget);
    expect(find.text('20°C'), findsOneWidget);

    device.at = (40.04, -100.04); // rounds to 40.0,-100.0
    await reload(tester);

    // B's forecast is up (50°F = 10°C); its /current is still pending.
    expect(backend.paths, contains('/api/weather/current/40.0,-100.0'));
    expect(find.text('10°C'), findsOneWidget);
    expect(find.text('68%'), findsNothing);
    expect(find.text('1010 hPa'), findsNothing);
    expect(_row('Humidity', 'Not available'), findsOneWidget);

    // B's answer lands and is shown.
    pendingB.complete((
      200,
      _current({'relativeHumidityPercent': 41, 'barometricPressureHpa': 990}),
    ));
    await _settle(tester);
    expect(_row('Humidity', '41%'), findsOneWidget);
  });

  testWidgets('a late /current for the old location is never applied', (
    tester,
  ) async {
    // A's second (refresh) /current hangs; the user has moved to B by then.
    final lateA = Completer<(int, Object?)>();
    var aCalls = 0;
    final backend = _RecordingBackend(
      forecastTemperature: (path) => path.contains('45.0') ? 68 : 50,
      currentHandler: (uri) {
        if (uri.path.endsWith('45.0,-93.3')) {
          aCalls++;
          if (aCalls == 1) {
            return Future.value((
              200,
              _current({'relativeHumidityPercent': 30}),
            ));
          }
          return lateA.future;
        }
        return Future.value((200, _current({'relativeHumidityPercent': 41})));
      },
    );
    final device = _Device(permission: 2);
    await _pump(tester, device: device, backend: backend);

    await reload(tester); // A again: /current pending
    device.at = (40.04, -100.04);
    await reload(tester); // B: fully loaded
    expect(_row('Humidity', '41%'), findsOneWidget);

    lateA.complete((200, _current({'relativeHumidityPercent': 99})));
    await _settle(tester);
    expect(find.text('99%'), findsNothing);
    expect(_row('Humidity', '41%'), findsOneWidget);
  });

  testWidgets('a /current failure after a success drops the old values', (
    tester,
  ) async {
    var calls = 0;
    final backend = _RecordingBackend(
      currentHandler: (uri) async {
        calls++;
        return calls == 1
            ? (
                200,
                _current({
                  'relativeHumidityPercent': 68,
                  'barometricPressureHpa': 1010,
                }),
              )
            : (500, {'success': false});
      },
    );
    await _pump(tester, device: _Device(permission: 2), backend: backend);
    expect(_row('Humidity', '68%'), findsOneWidget);

    await reload(tester);

    expect(calls, 2);
    expect(find.text('68%'), findsNothing);
    expect(find.text('1010 hPa'), findsNothing);
    expect(_row('Humidity', 'Not available'), findsOneWidget);
    expect(_row('Pressure', 'Not available'), findsOneWidget);
  });
}
