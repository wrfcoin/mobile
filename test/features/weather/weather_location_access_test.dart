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
import 'package:wrfcoin_mobile/features/weather/presentation/screens/alerts_screen.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_dashboard.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_detail_screen.dart';
import 'package:wrfcoin_mobile/services/offline/offline_data_buffer.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/fakes.dart';

/// mobile#327 and mobile#328: the Weather tab says *why* it has no location
/// and offers the action that fixes it. It asks for permission only on an
/// explicit tap, and it falls back to the last-known position when a fresh
/// fix times out.
///
/// Driven through the real Geolocator method channel and the real
/// [WeatherRepository] over a recording HTTP adapter, so the tests run
/// unchanged against the pre-fix app.

const _geolocator = MethodChannel('flutter.baseflow.com/geolocator');

const _allowLocationMessage = 'Allow location to see your local forecast';
const _allowButton = 'Allow location';
const _openSettingsButton = 'Open settings';
const _servicesOffMessage = 'Turn on Location to see your local forecast';
const _servicesOffButton = 'Turn on Location';
const _noFixMessage = "Couldn't get a location fix";
const _retryButton = 'Retry';

/// Exact fix; rounded to 0.1° it is 45.0,-93.3.
const _fresh = (44.98765, -93.26543);

/// A cached fix elsewhere; rounded to 0.1° it is 40.7,-74.0.
const _lastKnown = (40.71278, -74.00594);

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

Map<String, dynamic> _forecastEnvelope() => {
  'location': {'latitude': 45.0, 'longitude': -93.3, 'name': '45.0,-93.3'},
  'forecast': {
    'periods': [
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

Map<String, dynamic> _alertsEnvelope() => {
  'alerts': <Object?>[],
  'count': 0,
  'source': 'NOAA-NWS',
  'timestamp': '2026-09-28T17:00:00.000Z',
  'status': 'success',
};

/// Records every request; answers the forecast and alerts routes.
class _RecordingBackend implements HttpClientAdapter {
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
    final Object? body;
    if (path.startsWith('/api/weather/alerts/')) {
      body = _alertsEnvelope();
    } else if (path.startsWith('/api/weather/forecast/')) {
      body = _forecastEnvelope();
    } else {
      body = {'success': false};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      body is Map && body['success'] == false ? 404 : 200,
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

/// Geolocator platform state for one test.
class _Device {
  _Device({
    required this.permission,
    this.grantOnRequest,
    this.servicesOn = true,
    this.fix = true,
    this.hang = false,
    this.lastKnown,
  });

  /// 0 denied, 1 deniedForever, 2 whileInUse, 3 always.
  int permission;

  /// What the permission dialog answers; null leaves [permission] as it is.
  int? grantOnRequest;

  bool servicesOn;

  void Function()? onFreshFix;

  /// Whether a fresh fix arrives (false: the plugin reports an error).
  bool fix;

  /// The fresh fix never answers; only the 15 s timeLimit ends it.
  bool hang;

  /// The platform's cached position, if any.
  (double, double)? lastKnown;

  final calls = <String>[];
  final arguments = <String, Object?>{};

  int count(String method) => calls.where((c) => c == method).length;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    arguments[call.method] = call.arguments;
    switch (call.method) {
      case 'checkPermission':
        return permission;
      case 'requestPermission':
        permission = grantOnRequest ?? permission;
        return permission;
      case 'isLocationServiceEnabled':
        return servicesOn;
      case 'openAppSettings':
      case 'openLocationSettings':
        return true;
      case 'getLastKnownPosition':
        final at = lastKnown;
        return at == null ? null : _position(at);
      case 'getCurrentPosition':
        if (hang) return Completer<Object?>().future;
        if (!fix) throw PlatformException(code: 'LOCATION_UNAVAILABLE');
        onFreshFix?.call();
        return _position(_fresh);
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

Future<void> _tap(WidgetTester tester, String label) async {
  final button = find.text(label, skipOffstage: false);
  expect(button, findsOneWidget, reason: 'a "$label" button');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _settle(tester);
}

/// Waits out the plugin's 15 s timeLimit on a fix that never arrives.
Future<void> _waitOutFix(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 16));
  await _settle(tester);
}

const _forecastAtFresh = '/api/weather/forecast/45.0,-93.3';
const _currentAtFresh = '/api/weather/current/45.0,-93.3';
const _alertsAtFresh = '/api/weather/alerts/45.0,-93.3';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('#327 Allow location button', () {
    testWidgets('denied: the card shows an "Allow location" button', (
      tester,
    ) async {
      final device = _Device(permission: 0);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);

      expect(find.text(_allowLocationMessage), findsOneWidget);
      expect(find.text(_allowButton), findsOneWidget);
      // Nothing is asked or sent before the tap.
      expect(device.calls, isNot(contains('requestPermission')));
      expect(backend.requests, isEmpty);
    });

    testWidgets('a tap asks for permission; a grant reloads exactly once', (
      tester,
    ) async {
      final device = _Device(permission: 0, grantOnRequest: 2);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);
      expect(backend.requests, isEmpty);

      await _tap(tester, _allowButton);

      expect(device.count('requestPermission'), 1);
      expect(backend.paths, [
        _forecastAtFresh,
        _currentAtFresh,
        _alertsAtFresh,
      ]);
      expect(find.text(_allowLocationMessage), findsNothing);
    });

    testWidgets('a tap answered "deny": no request', (tester) async {
      final device = _Device(permission: 0, grantOnRequest: 0);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);

      await _tap(tester, _allowButton);

      expect(device.count('requestPermission'), 1);
      expect(backend.requests, isEmpty);
      expect(find.text(_allowLocationMessage), findsOneWidget);
    });

    testWidgets('deniedForever: the tap opens app settings, never a request', (
      tester,
    ) async {
      final device = _Device(permission: 1);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);

      // Android won't show the dialog again, and the card says so.
      expect(find.textContaining("Android won't ask again"), findsOneWidget);
      await _tap(tester, _openSettingsButton);

      expect(device.count('openAppSettings'), 1);
      expect(device.calls, isNot(contains('requestPermission')));
      expect(backend.requests, isEmpty);
    });

    testWidgets('the dialog answers deniedForever: explains, then settings', (
      tester,
    ) async {
      final device = _Device(permission: 0, grantOnRequest: 1);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);

      await _tap(tester, _allowButton);
      expect(find.textContaining("Android won't ask again"), findsOneWidget);
      expect(device.calls, isNot(contains('openAppSettings')));

      await _tap(tester, _openSettingsButton);
      expect(device.count('openAppSettings'), 1);
      expect(device.count('requestPermission'), 1);
      expect(backend.requests, isEmpty);
    });

    testWidgets('alerts screen: the same button, never "all clear"', (
      tester,
    ) async {
      final device = _Device(permission: 0, grantOnRequest: 2);
      final backend = _RecordingBackend();
      await _pump(
        tester,
        device: device,
        backend: backend,
        home: const AlertsScreen(),
      );
      expect(find.text('All clear in your area'), findsNothing);

      await _tap(tester, _allowButton);

      expect(backend.paths, [
        _forecastAtFresh,
        _currentAtFresh,
        _alertsAtFresh,
      ]);
    });

    testWidgets('forecast detail: the button grants and reloads the detail', (
      tester,
    ) async {
      final device = _Device(permission: 0, grantOnRequest: 2);
      final backend = _RecordingBackend();
      await _pump(
        tester,
        device: device,
        backend: backend,
        home: const ForecastDetailScreen(),
      );
      expect(backend.requests, isEmpty);

      await _tap(tester, _allowButton);

      expect(device.count('requestPermission'), 1);
      expect(backend.requests, isNotEmpty);
      for (final path in backend.paths) {
        expect(path, startsWith(_forecastAtFresh));
      }
    });
  });

  group('#328 fix fallback and distinct reasons', () {
    testWidgets('the fresh fix asks for balanced (medium) accuracy', (
      tester,
    ) async {
      final device = _Device(permission: 2);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);

      final args = device.arguments['getCurrentPosition'] as Map;
      expect(args['accuracy'], 2, reason: 'LocationAccuracy.medium.index');
      expect(backend.paths, [
        _forecastAtFresh,
        _currentAtFresh,
        _alertsAtFresh,
      ]);
    });

    testWidgets('fix times out, last-known exists: forecast at its 0.1° cell', (
      tester,
    ) async {
      final device = _Device(permission: 2, hang: true, lastKnown: _lastKnown);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);
      expect(backend.requests, isEmpty, reason: 'fresh fix still pending');

      await _waitOutFix(tester);

      expect(device.count('getLastKnownPosition'), 1);
      expect(backend.paths, [
        '/api/weather/forecast/40.7,-74.0',
        '/api/weather/current/40.7,-74.0',
        '/api/weather/alerts/40.7,-74.0',
      ]);
      for (final uri in backend.requests) {
        final text = Uri.decodeFull(uri.toString());
        expect(text, isNot(contains('40.71')), reason: 'no exact latitude');
        expect(text, isNot(contains('74.00')), reason: 'no exact longitude');
      }
    });

    testWidgets('fix errors, last-known exists: forecast at its 0.1° cell', (
      tester,
    ) async {
      final device = _Device(permission: 2, fix: false, lastKnown: _lastKnown);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);

      expect(backend.paths, [
        '/api/weather/forecast/40.7,-74.0',
        '/api/weather/current/40.7,-74.0',
        '/api/weather/alerts/40.7,-74.0',
      ]);
    });

    testWidgets('fix times out, no last-known: "no fix", never "Allow"', (
      tester,
    ) async {
      final device = _Device(permission: 2, hang: true);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);
      await _waitOutFix(tester);

      expect(find.text(_noFixMessage), findsOneWidget);
      expect(find.text(_allowLocationMessage), findsNothing);
      expect(find.text(_allowButton), findsNothing);
      expect(backend.requests, isEmpty);
      expect(device.calls, isNot(contains('requestPermission')));
    });

    testWidgets('"no fix" Retry resolves again and loads once a fix exists', (
      tester,
    ) async {
      final device = _Device(permission: 2, fix: false);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);
      expect(find.text(_noFixMessage), findsOneWidget);
      expect(backend.requests, isEmpty);

      device.fix = true;
      await _tap(tester, _retryButton);

      expect(backend.paths, [
        _forecastAtFresh,
        _currentAtFresh,
        _alertsAtFresh,
      ]);
    });

    testWidgets('location services off: "Turn on Location", no request', (
      tester,
    ) async {
      final device = _Device(permission: 2, servicesOn: false);
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);

      expect(find.text(_servicesOffMessage), findsOneWidget);
      expect(find.text(_allowLocationMessage), findsNothing);
      expect(device.calls, isNot(contains('getCurrentPosition')));
      expect(backend.requests, isEmpty);

      await _tap(tester, _servicesOffButton);
      expect(device.count('openLocationSettings'), 1);
      expect(backend.requests, isEmpty);

      device.servicesOn = true;
      await _tap(tester, _retryButton);
      expect(backend.paths, [
        _forecastAtFresh,
        _currentAtFresh,
        _alertsAtFresh,
      ]);
    });
  });

  group('mobile#331: permission/services change as a fresh fix returns', () {
    testWidgets('fresh fix arrives after revoke: no HTTP, Allow location', (
      tester,
    ) async {
      final device = _Device(permission: 2);
      device.onFreshFix = () => device.permission = 0;
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);
      expect(device.count('getCurrentPosition'), 1);
      expect(device.calls, isNot(contains('getLastKnownPosition')));
      expect(backend.requests, isEmpty);
      expect(find.text(_allowLocationMessage), findsOneWidget);
    });

    testWidgets('fresh fix arrives after services off: no HTTP, turn on', (
      tester,
    ) async {
      final device = _Device(permission: 2);
      device.onFreshFix = () => device.servicesOn = false;
      final backend = _RecordingBackend();
      await _pump(tester, device: device, backend: backend);
      expect(device.count('getCurrentPosition'), 1);
      expect(device.calls, isNot(contains('getLastKnownPosition')));
      expect(backend.requests, isEmpty);
      expect(find.text(_servicesOffMessage), findsOneWidget);
    });
  });

  group('review round 1 P1: permission revoked mid-fresh-fix', () {
    testWidgets(
      'revoke while the 15s fresh fix hangs: no last-known use, no request',
      (tester) async {
        final device = _Device(
          permission: 2,
          hang: true,
          lastKnown: _lastKnown,
        );
        final backend = _RecordingBackend();
        await _pump(tester, device: device, backend: backend);
        expect(backend.requests, isEmpty, reason: 'fresh fix still pending');

        // Revoke while the fresh fix is still outstanding (mobile#324
        // invariant: a revoke during the wait must not leak a cached
        // position; PR #329 review round 1 P1).
        device.permission = 0;
        await _waitOutFix(tester);

        expect(
          device.calls,
          isNot(contains('getLastKnownPosition')),
          reason: 'permission was revoked before last-known was consulted',
        );
        expect(backend.requests, isEmpty);
        expect(find.text(_allowLocationMessage), findsOneWidget);
        expect(find.text(_allowButton), findsOneWidget);
      },
    );

    testWidgets(
      'services turned off while the 15s fresh fix hangs: no request',
      (tester) async {
        final device = _Device(
          permission: 2,
          hang: true,
          lastKnown: _lastKnown,
        );
        final backend = _RecordingBackend();
        await _pump(tester, device: device, backend: backend);
        expect(backend.requests, isEmpty, reason: 'fresh fix still pending');

        device.servicesOn = false;
        await _waitOutFix(tester);

        expect(device.calls, isNot(contains('getLastKnownPosition')));
        expect(backend.requests, isEmpty);
        expect(find.text(_servicesOffMessage), findsOneWidget);
      },
    );
  });
}
