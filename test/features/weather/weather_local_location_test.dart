import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/services/offline/offline_data_buffer.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/alerts_screen.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_dashboard.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/widgets/weather_card.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/fakes.dart';

/// The Weather tab is keyed by the device's location rounded to 0.1° on the
/// device (owner ruling 2026-09-28). Without a location it makes no request;
/// it never sends the placeholder 'local', never the exact fix, and never
/// shows a forecast of zeros.
///
/// The test drives the real Geolocator method channel and the real
/// [WeatherRepository] over a recording HTTP adapter, so it runs unchanged
/// against the pre-fix app.

const _geolocator = MethodChannel('flutter.baseflow.com/geolocator');
const _allowLocation = 'Allow location to see your local forecast';
const _noFix = "Couldn't get a location fix";

/// Exact fix; rounded to 0.1° it is 45.0,-93.3.
const _exactLat = 44.98765;
const _exactLon = -93.26543;

/// The backend's forecast envelope (NOAA-NWS daily periods).
Map<String, dynamic> forecastEnvelope({List<Map<String, dynamic>>? periods}) =>
    {
      'location': {'latitude': 45.0, 'longitude': -93.3, 'name': '45.0,-93.3'},
      'forecast': {
        'periods':
            periods ??
            [
              {
                'number': 1,
                'name': 'Tonight',
                'startTime': '2026-09-28T18:00:00-05:00',
                'isDaytime': false,
                'temperature': 68,
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

/// The backend's alerts envelope.
Map<String, dynamic> alertsEnvelope() => {
  'location': {'latitude': 45.0, 'longitude': -93.3, 'name': '45.0,-93.3'},
  'alerts': [
    {
      'id': 'urn:oid:2.49.0.1.840.0.test',
      'areaDesc': 'Hennepin',
      'sent': '2026-09-28T16:00:00-05:00',
      'effective': '2026-09-28T16:00:00-05:00',
      'severity': 'Moderate',
      'event': 'Wind Advisory',
      'headline': 'Wind Advisory until 9 PM',
      'description': 'Gusts up to 45 mph.',
    },
  ],
  'count': 1,
  'source': 'NOAA-NWS',
  'timestamp': '2026-09-28T17:00:00.000Z',
  'status': 'success',
};

/// Records every request and answers the two weather routes; anything else
/// is the backend's catch-all 404.
class _RecordingBackend implements HttpClientAdapter {
  _RecordingBackend({
    this.forecastBody,
    this.alertsBody,
    this.forecastStatus = 200,
    this.alertsStatus = 200,
  });

  Object? forecastBody;
  Object? alertsBody;
  int forecastStatus;
  int alertsStatus;

  /// When set, the forecast response waits for it.
  Completer<void>? forecastGate;

  /// When set, the alerts response waits for it.
  Completer<void>? alertsGate;
  final requests = <Uri>[];

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
    if (path.startsWith('/api/weather/forecast/')) {
      await forecastGate?.future;
      body = forecastBody;
      status = forecastStatus;
    } else if (path.startsWith('/api/weather/alerts/')) {
      await alertsGate?.future;
      body = alertsBody;
      status = alertsStatus;
    } else {
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

/// No connectivity plugin in tests: a stream that changes only when a test
/// calls [reconnect].
class _TestConnectivity extends Fake implements Connectivity {
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();

  void reconnect() => _changes.add(const [ConnectivityResult.wifi]);

  Future<void> close() => _changes.close();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}

/// Geolocator platform state for one test.
class _Device {
  _Device({
    required this.permission,
    this.fix = true,
    this.hang = false,
    this.hangPermission = false,
  });

  /// 0 denied, 1 deniedForever, 2 whileInUse, 3 always.
  int permission;

  /// Whether a position fix arrives.
  final bool fix;

  /// The position request never answers.
  final bool hang;

  /// The permission check never answers (no plugin timeout covers it).
  final bool hangPermission;

  final calls = <String>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'checkPermission':
        if (hangPermission) return Completer<Object?>().future;
        return permission;
      case 'requestPermission':
        return permission;
      case 'isLocationServiceEnabled':
        return true;
      case 'getCurrentPosition':
        if (hang) return Completer<Object?>().future;
        if (!fix) {
          throw PlatformException(code: 'LOCATION_UNAVAILABLE');
        }
        return <String, Object?>{
          'latitude': _exactLat,
          'longitude': _exactLon,
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

Future<ProviderContainer> _pumpWeatherTab(
  WidgetTester tester, {
  required _Device device,
  required _RecordingBackend backend,
  Widget home = const ForecastDashboard(),
  _TestConnectivity? connectivity,
  List<Override> overrides = const [],
}) async {
  final network = connectivity ?? _TestConnectivity();
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
        // The real offline buffer (the path that used to build a forecast of
        // zeros), minus the connectivity plugin.
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
        ...overrides,
      ],
      child: MaterialApp(home: home),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// Lets real async work (database, HTTP adapter) and frames run.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A weather notifier whose loads end without an alerts answer, counting
/// how often the alerts screen asks for one.
class _UnansweredWeather extends WeatherNotifier {
  int loads = 0;

  @override
  WeatherState build() => const WeatherState();

  @override
  Future<void> loadLocalWeather() async {
    loads++;
    state = const WeatherState(loading: true);
    // Across a frame, so the screen sees the load start and end.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    state = const WeatherState();
  }
}

Future<Map<String, dynamic>?> _widgetSnapshot() async {
  final raw = (await SharedPreferences.getInstance()).getString(
    'home_widget_snapshot_v1',
  );
  return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // mobile#328: permission is granted, so a missing fix must not say
  // "Allow location".
  testWidgets('no position yet: no request, says there is no fix', (
    tester,
  ) async {
    final backend = _RecordingBackend(
      forecastBody: forecastEnvelope(),
      alertsBody: alertsEnvelope(),
    );
    await _pumpWeatherTab(
      tester,
      device: _Device(permission: 2, fix: false),
      backend: backend,
    );

    expect(backend.requests, isEmpty);
    expect(find.text(_noFix, skipOffstage: false), findsOneWidget);
    expect(find.text(_allowLocation, skipOffstage: false), findsNothing);
    expect(find.byType(WeatherCard, skipOffstage: false), findsNothing);
  });

  for (final (label, permission) in [('denied', 0), ('deniedForever', 1)]) {
    testWidgets('$label: no request and no permission prompt', (tester) async {
      final device = _Device(permission: permission);
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      await _pumpWeatherTab(tester, device: device, backend: backend);

      expect(backend.requests, isEmpty);
      expect(device.calls, isNot(contains('requestPermission')));
      expect(device.calls, isNot(contains('getCurrentPosition')));
      expect(find.text(_allowLocation, skipOffstage: false), findsOneWidget);
    });
  }

  testWidgets('granted: only the 0.1°-rounded position is sent', (
    tester,
  ) async {
    final device = _Device(permission: 2);
    final backend = _RecordingBackend(
      forecastBody: forecastEnvelope(),
      alertsBody: alertsEnvelope(),
    );
    await _pumpWeatherTab(tester, device: device, backend: backend);

    expect(device.calls, isNot(contains('requestPermission')));
    expect(backend.requests.map((u) => u.toString()).toSet(), {
      'https://tailnet.test:9444/api/weather/forecast/45.0,-93.3?days=14',
      'https://tailnet.test:9444/api/weather/current/45.0,-93.3',
      'https://tailnet.test:9444/api/weather/alerts/45.0,-93.3',
    });
    for (final uri in backend.requests) {
      final text = Uri.decodeFull(uri.toString());
      expect(text, isNot(contains('local')));
      expect(text, isNot(contains('44.98')), reason: 'no exact latitude');
      expect(text, isNot(contains('93.26')), reason: 'no exact longitude');
      expect(text, isNot(contains('wrf-forecast')));
      // Only the fixed forecast query; nothing about the device.
      expect(uri.queryParameters.keys, anyOf(isEmpty, ['days']));
    }
  });

  testWidgets('envelopes: forecast and alerts parse from the backend shape', (
    tester,
  ) async {
    final backend = _RecordingBackend(
      forecastBody: forecastEnvelope(),
      alertsBody: alertsEnvelope(),
    );
    final container = await _pumpWeatherTab(
      tester,
      device: _Device(permission: 3),
      backend: backend,
    );

    final state = container.read(weatherProvider);
    expect(state.error, isNull);
    final forecast = state.forecast!;
    expect(forecast.temperature, closeTo(20.0, 1e-9), reason: '68 °F');
    expect(forecast.windSpeed, closeTo(16.09344, 1e-9), reason: '10 mph');
    expect(forecast.windDirection, 'NW');
    expect(forecast.timestamp, '2026-09-28T18:00:00-05:00');
    // Daily NOAA periods carry none of these: absent, not zero.
    expect(forecast.humidity, isNull);
    expect(forecast.pressure, isNull);
    expect(forecast.precipitation, isNull);
    expect(forecast.aqi, isNull);

    expect(state.alerts, hasLength(1));
    final alert = state.alerts.single;
    expect(alert.id, 'urn:oid:2.49.0.1.840.0.test');
    expect(alert.type, 'Wind Advisory');
    expect(alert.severity, 'Moderate');
    expect(alert.location, 'Hennepin');
    expect(alert.timestamp, '2026-09-28T16:00:00-05:00');
    expect(alert.description, 'Wind Advisory until 9 PM');

    expect(find.byType(WeatherCard, skipOffstage: false), findsOneWidget);
    expect(find.text('1 active alert', skipOffstage: false), findsOneWidget);
  });

  final empties = <String, Object>{
    'empty list': <Object>[],
    'envelope without periods': forecastEnvelope(periods: const []),
  };
  empties.forEach((label, body) {
    testWidgets('$label: no forecast of zeros, nothing written to the widget', (
      tester,
    ) async {
      final backend = _RecordingBackend(
        forecastBody: body,
        alertsBody: alertsEnvelope(),
      );
      final container = await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
      );

      expect(container.read(weatherProvider).forecast, isNull);
      expect(find.byType(WeatherCard, skipOffstage: false), findsNothing);
      final snapshot = await _widgetSnapshot();
      expect(snapshot?['weatherTemperature'], isNull);
      expect(snapshot?['weatherPressure'], isNull);
    });
  });

  // The forecast's own failure must stay on screen whatever the alerts call
  // returns (review of #324, P2-1).
  const serverError = 'Server error. Please try again later.';
  const noForecast = 'No forecast is available for your area right now.';
  final forecastFailures = <String, (Object, int, String)>{
    'empty list': (<Object>[], 200, noForecast),
    'zero periods': (forecastEnvelope(periods: const []), 200, noForecast),
    '500': (<String, Object>{'error': true}, 500, serverError),
  };
  for (final MapEntry(key: label, value: (body, status, text))
      in forecastFailures.entries) {
    for (final alertsOk in [true, false]) {
      final alertsLabel = alertsOk ? 'alerts OK' : 'alerts 500';
      testWidgets('forecast $label, $alertsLabel: the forecast failure shows', (
        tester,
      ) async {
        final backend = _RecordingBackend(
          forecastBody: body,
          forecastStatus: status,
          alertsBody: alertsEnvelope(),
          alertsStatus: alertsOk ? 200 : 500,
        );
        final container = await _pumpWeatherTab(
          tester,
          device: _Device(permission: 2),
          backend: backend,
        );

        final state = container.read(weatherProvider);
        expect(state.forecast, isNull);
        expect(state.error?.message, text);
        expect(find.text(text, skipOffstage: false), findsOneWidget);
        expect(
          find.text('Pull to refresh weather data', skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(WeatherCard, skipOffstage: false), findsNothing);
      });
    }
  }

  testWidgets('no resolver timer outlives the tab when the fix never arrives', (
    tester,
  ) async {
    final backend = _RecordingBackend(
      forecastBody: forecastEnvelope(),
      alertsBody: alertsEnvelope(),
    );
    await _pumpWeatherTab(
      tester,
      device: _Device(permission: 2, hang: true),
      backend: backend,
    );
    expect(backend.requests, isEmpty);

    // Disposing the tree must cancel the resolver's 20 s timeout. The
    // plugin's own 15 s timeLimit timer (it cancels the native request) is
    // bounded and drains here; a resolver timer left running would still be
    // pending, and the test binding fails the test on it.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets(
    'dispose cancels the 20 s bound when the permission check hangs',
    (tester) async {
      // No plugin timeout covers checkPermission, so only the dispose cancel
      // stops the resolver's timer here.
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2, hangPermission: true),
        backend: backend,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(backend.requests, isEmpty);
    },
  );

  testWidgets('the plugin timeLimit ends a fix that never arrives at 15 s', (
    tester,
  ) async {
    // Only Geolocator's timeLimit makes the Android plugin cancel the native
    // request (cancelGetCurrentPosition); it fires before the 20 s bound.
    final backend = _RecordingBackend(
      forecastBody: forecastEnvelope(),
      alertsBody: alertsEnvelope(),
    );
    final container = await _pumpWeatherTab(
      tester,
      device: _Device(permission: 2, hang: true),
      backend: backend,
    );

    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(container.read(weatherProvider).locationNeeded, isTrue);
    expect(backend.requests, isEmpty);
  });

  testWidgets('the 20 s bound ends a resolution that never answers', (
    tester,
  ) async {
    final backend = _RecordingBackend(
      forecastBody: forecastEnvelope(),
      alertsBody: alertsEnvelope(),
    );
    final container = await _pumpWeatherTab(
      tester,
      device: _Device(permission: 2, hangPermission: true),
      backend: backend,
    );

    await tester.pump(const Duration(seconds: 19));
    expect(container.read(weatherProvider).loading, isTrue);
    expect(container.read(weatherProvider).locationNeeded, isFalse);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(container.read(weatherProvider).locationNeeded, isTrue);
    expect(container.read(weatherProvider).loading, isFalse);
    expect(find.text(_noFix, skipOffstage: false), findsOneWidget);
    expect(backend.requests, isEmpty);
  });

  // "All clear" is a safety claim: only a successful alerts response with no
  // alerts may make it (review of #324, P2-3).
  group('alerts screen', () {
    const allClear = 'All clear in your area';
    const noActive = 'No Active Alerts';
    const unavailable = 'Alerts unavailable';

    testWidgets('alerts 500: unavailable, never all clear', (tester) async {
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: <String, Object>{'error': true},
        alertsStatus: 500,
      );
      final container = await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
        home: const AlertsScreen(),
      );

      expect(container.read(weatherProvider).alertsError, isNotNull);
      expect(find.text(unavailable), findsOneWidget);
      expect(find.text(allClear), findsNothing);
      expect(find.text(noActive), findsNothing);
    });

    testWidgets('no location: asks for location, never all clear', (
      tester,
    ) async {
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      await _pumpWeatherTab(
        tester,
        device: _Device(permission: 0),
        backend: backend,
        home: const AlertsScreen(),
      );

      expect(backend.requests, isEmpty);
      expect(find.text(_allowLocation), findsOneWidget);
      expect(find.text(allClear), findsNothing);
      expect(find.text(noActive), findsNothing);
    });

    testWidgets('alerts OK with none: all clear', (tester) async {
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: <String, Object>{'alerts': <Object>[], 'count': 0},
      );
      await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
        home: const AlertsScreen(),
      );

      expect(find.text(allClear), findsOneWidget);
      expect(find.text(unavailable), findsNothing);
    });

    testWidgets('alerts OK with one: the alert, not all clear', (tester) async {
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
        home: const AlertsScreen(),
      );

      expect(find.text('Wind Advisory'), findsOneWidget);
      expect(find.text(allClear), findsNothing);
    });

    testWidgets('opened during a forecast-only refresh: loads alerts', (
      tester,
    ) async {
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      final show = ValueNotifier(false);
      addTearDown(show.dispose);
      final container = await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
        home: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, visible, _) =>
              visible ? const AlertsScreen() : const SizedBox.shrink(),
        ),
      );

      // The reconnect path refreshes only the forecast; the screen opens
      // while that response is still in flight.
      final gate = backend.forecastGate = Completer<void>();
      unawaited(
        container
            .read(weatherProvider.notifier)
            .loadForecast(CoarseLocation.round(45.0, -93.3)),
      );
      await tester.pump();
      expect(container.read(weatherProvider).loading, isTrue);
      show.value = true;
      await tester.pump();
      await tester.pump();
      gate.complete();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        backend.requests.map((u) => u.path),
        contains('/api/weather/alerts/45.0,-93.3'),
      );
      expect(find.text('Wind Advisory'), findsOneWidget);
      expect(find.text(allClear), findsNothing);
    });

    testWidgets('dashboard: forecast OK, alerts 500 says alerts unavailable', (
      tester,
    ) async {
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: <String, Object>{'error': true},
        alertsStatus: 500,
      );
      await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
      );

      expect(find.byType(WeatherCard, skipOffstage: false), findsOneWidget);
      expect(find.text(unavailable, skipOffstage: false), findsOneWidget);
    });
  });

  // Review of #324, round 3.
  group('revocation and stale results', () {
    const allClear = 'All clear in your area';

    testWidgets('P1-1: revoked, refreshed, reconnected: no request', (
      tester,
    ) async {
      final device = _Device(permission: 2);
      final network = _TestConnectivity();
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      final container = await _pumpWeatherTab(
        tester,
        device: device,
        backend: backend,
        connectivity: network,
      );
      expect(backend.requests, hasLength(3));

      device.permission = 0;
      unawaited(container.read(weatherProvider.notifier).loadLocalWeather());
      await _settle(tester);
      expect(container.read(weatherProvider).locationNeeded, isTrue);

      network.reconnect();
      await _settle(tester);

      expect(backend.requests, hasLength(3), reason: 'no request after revoke');
      expect(container.read(weatherProvider).locationNeeded, isTrue);
      expect(find.text(_allowLocation, skipOffstage: false), findsOneWidget);
      expect(find.byType(WeatherCard, skipOffstage: false), findsNothing);
    });

    testWidgets('reconnect with permission reloads forecast and alerts', (
      tester,
    ) async {
      final network = _TestConnectivity();
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
        connectivity: network,
      );
      expect(backend.requests, hasLength(3));

      network.reconnect();
      await _settle(tester);

      expect(backend.requests.map((u) => u.path), [
        '/api/weather/forecast/45.0,-93.3',
        '/api/weather/current/45.0,-93.3',
        '/api/weather/alerts/45.0,-93.3',
        '/api/weather/forecast/45.0,-93.3',
        '/api/weather/current/45.0,-93.3',
        '/api/weather/alerts/45.0,-93.3',
      ]);
    });

    testWidgets('P2-4: a late alerts answer after revoke: no all clear', (
      tester,
    ) async {
      final device = _Device(permission: 2);
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: <String, Object>{'alerts': <Object>[], 'count': 0},
      );
      final gate = backend.alertsGate = Completer<void>();
      final container = await _pumpWeatherTab(
        tester,
        device: device,
        backend: backend,
        home: const AlertsScreen(),
      );
      expect(backend.requests.last.path, '/api/weather/alerts/45.0,-93.3');

      device.permission = 0;
      unawaited(container.read(weatherProvider.notifier).loadLocalWeather());
      await _settle(tester);
      gate.complete();
      await _settle(tester);

      final state = container.read(weatherProvider);
      expect(state.locationNeeded, isTrue);
      expect(state.alertsLoaded, isFalse);
      expect(find.text(_allowLocation), findsOneWidget);
      expect(find.text(allClear), findsNothing);
    });

    testWidgets('P2-4: a late forecast answer after revoke: no forecast', (
      tester,
    ) async {
      final device = _Device(permission: 2);
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      final gate = backend.forecastGate = Completer<void>();
      final container = await _pumpWeatherTab(
        tester,
        device: device,
        backend: backend,
      );

      device.permission = 0;
      unawaited(container.read(weatherProvider.notifier).loadLocalWeather());
      await _settle(tester);
      gate.complete();
      await _settle(tester);

      final state = container.read(weatherProvider);
      expect(state.locationNeeded, isTrue);
      expect(state.forecast, isNull);
      expect(find.byType(WeatherCard, skipOffstage: false), findsNothing);
      expect(find.text(_allowLocation, skipOffstage: false), findsOneWidget);
      expect(
        backend.requests.where((u) => u.path.contains('/alerts/')),
        isEmpty,
        reason: 'the superseded load stops before its alerts half',
      );
    });

    testWidgets('M9: before any alerts answer: spinner, never all clear', (
      tester,
    ) async {
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: <String, Object>{'alerts': <Object>[], 'count': 0},
      );
      final gate = backend.alertsGate = Completer<void>();
      await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
        home: const AlertsScreen(),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(allClear), findsNothing);
      expect(find.text('No Active Alerts'), findsNothing);

      gate.complete();
      await _settle(tester);
      expect(find.text(allClear), findsOneWidget);
    });

    testWidgets('M10: one load per open, even if a load ends unanswered', (
      tester,
    ) async {
      final notifier = _UnansweredWeather();
      await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: _RecordingBackend(),
        home: const AlertsScreen(),
        overrides: [weatherProvider.overrideWith(() => notifier)],
      );
      await _settle(tester);

      expect(notifier.loads, 1);
    });

    testWidgets('open during a full load: one forecast and one alerts call', (
      tester,
    ) async {
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      final show = ValueNotifier(false);
      addTearDown(show.dispose);
      final container = await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
        home: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, visible, _) =>
              visible ? const AlertsScreen() : const SizedBox.shrink(),
        ),
      );

      final gate = backend.forecastGate = Completer<void>();
      unawaited(container.read(weatherProvider.notifier).loadLocalWeather());
      await tester.pump();
      show.value = true;
      await tester.pump();
      await tester.pump();
      gate.complete();
      await _settle(tester);

      expect(backend.requests.map((u) => u.path), [
        '/api/weather/forecast/45.0,-93.3',
        '/api/weather/current/45.0,-93.3',
        '/api/weather/alerts/45.0,-93.3',
      ]);
      expect(find.text('Wind Advisory'), findsOneWidget);
    });

    testWidgets('M11: a failed alerts refresh drops the old alerts', (
      tester,
    ) async {
      final backend = _RecordingBackend(
        forecastBody: forecastEnvelope(),
        alertsBody: alertsEnvelope(),
      );
      final container = await _pumpWeatherTab(
        tester,
        device: _Device(permission: 2),
        backend: backend,
      );
      expect(container.read(weatherProvider).alerts, hasLength(1));
      expect(find.text('1 active alert', skipOffstage: false), findsOneWidget);

      backend.alertsStatus = 500;
      unawaited(container.read(weatherProvider.notifier).loadLocalWeather());
      await _settle(tester);

      expect(container.read(weatherProvider).alerts, isEmpty);
      expect(find.text('1 active alert', skipOffstage: false), findsNothing);
      expect(
        find.text('Alerts unavailable', skipOffstage: false),
        findsOneWidget,
      );
    });
  });
}
