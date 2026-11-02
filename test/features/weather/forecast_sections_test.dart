// The hourly strip and daily list on the Weather tab: real data, one call per
// query, honest states, and the detail screen still reachable.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/core/time/app_clock.dart';
import 'package:wrfcoin_mobile/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_detail_screen.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/fakes.dart';
import '../../test_helpers/screenshot_fonts.dart';

final _now = DateTime(2026, 11, 1, 12);

/// No offset, so it parses as device-local time, as the test's clock is.
String _stamp(DateTime at) => at.toIso8601String();

Map<String, Object?> _hourlyEnvelope() => {
  'forecast': {
    'periods': [
      for (var hour = 0; hour < 24; hour++)
        {
          'startTime': _stamp(_now.add(Duration(hours: hour))),
          'temperature': 60 + hour,
          'temperatureUnit': 'F',
          'relativeHumidity': 70,
          'windSpeed': '10 mph',
          'windDirection': 'SSE',
          'shortForecast': hour == 1 ? 'Slight Chance Light Rain' : 'Cloudy',
          // NOAA leaves the chance out of some hours: nothing is invented.
          if (hour != 2)
            'probabilityOfPrecipitation': {
              'unitCode': 'wmoUnit:percent',
              'value': 30,
            },
        },
    ],
  },
};

Map<String, Object?> _dailyEnvelope() => {
  'forecast': {
    'periods': [
      for (var day = 0; day < 7; day++) ...[
        {
          'startTime': _stamp(_now.add(Duration(days: day))),
          'isDaytime': true,
          'temperature': 70,
          'temperatureUnit': 'F',
          'relativeHumidity': {'min': 62, 'max': 85},
          'windSpeed': '5 to 10 mph',
          'windDirection': 'S',
          'shortForecast': 'Sunny',
        },
        {
          'startTime': _stamp(_now.add(Duration(days: day, hours: 8))),
          'isDaytime': false,
          'temperature': 50,
          'temperatureUnit': 'F',
          'relativeHumidity': {'min': 62, 'max': 85},
          'windSpeed': '5 mph',
          'windDirection': 'S',
          'shortForecast': 'Clear',
        },
      ],
    ],
  },
};

class _Backend implements HttpClientAdapter {
  final requests = <Uri>[];
  int hourlyStatus = 200;
  int dailyStatus = 200;
  Object? hourlyBody = _hourlyEnvelope();

  List<Uri> get forecastRequests =>
      requests.where((u) => u.path.contains('/weather/forecast/')).toList();

  int get hourlyCalls => forecastRequests
      .where((u) => u.queryParameters['type'] == 'hourly')
      .length;

  int get dailyCalls => forecastRequests
      .where((u) => u.queryParameters['type'] != 'hourly')
      .length;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    requests.add(uri);
    Object? body = {'alerts': <Object?>[]};
    var status = 200;
    if (uri.path.contains('/weather/forecast/')) {
      final hourly = uri.queryParameters['type'] == 'hourly';
      body = hourly ? hourlyBody : _dailyEnvelope();
      status = hourly ? hourlyStatus : dailyStatus;
    } else if (uri.path.contains('/weather/current/')) {
      body = {'current': <String, Object?>{}};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  late AppDatabase db;
  late _Backend backend;
  late DateTime now;

  setUp(() {
    db = createTestDatabase();
    backend = _Backend();
    now = _now;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async => db.close());

  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool realFonts = true,
  }) async {
    if (realFonts) await loadFlutterCacheFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid/api'))
      ..httpClientAdapter = backend;
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
        weatherRepository: WeatherRepository(dio),
        weatherLocationResolver: FixedWeatherLocationResolver(
          CoarseLocation.round(45, -93.3),
        ),
        extraOverrides: [appClockProvider.overrideWithValue(() => now)],
      ),
    );
    await pumpFrames(tester, frames: 8);
    return ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>).first),
    ).read(appRouterProvider);
  }

  testWidgets('one call per query, with exactly what the edge admits', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(backend.dailyCalls, 1, reason: 'the card and the list share it');
    expect(backend.hourlyCalls, 1);
    final queries = backend.forecastRequests.map((u) => u.query).toSet();
    expect(queries, {'days=14', 'type=hourly&days=1'});
  });

  testWidgets('See all opens the detail with no further call', (tester) async {
    await pumpApp(tester);
    final before = backend.forecastRequests.length;

    await tester.ensureVisible(find.text('See all'));
    await tester.tap(find.text('See all'));
    await pumpUntilFound(tester, find.byType(ForecastDetailScreen));
    await pumpFrames(tester);

    expect(backend.forecastRequests.length, before);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Cloudy'), findsWidgets, reason: 'the detail has data');
  });

  testWidgets('a deep link to the detail still fetches its own data', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    now = now.add(const Duration(minutes: 11));
    router.go('/weather/forecast-detail');
    await pumpFrames(tester, frames: 8);
    expect(find.byType(ForecastDetailScreen), findsOneWidget);
    expect(find.text('Cloudy'), findsWidgets);
  });

  testWidgets('hours show time, temp, conditions, wind and rain if present', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(390, 2400));
    expect(find.text('Hourly'), findsOneWidget);
    expect(find.textContaining('Rain 30%'), findsWidgets);
    expect(find.textContaining('SSE'), findsWidgets);
    expect(find.text('Slight Chance Light Rain'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an hour without a rain chance shows none, not 0%', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(390, 2400));
    expect(find.text('Rain 0%'), findsNothing);
    expect(
      find.textContaining('Rain 30%'),
      findsNWidgets(23),
      reason: '24 hours, one with no chance',
    );
  });

  testWidgets('days show low and high, conditions, wind, humidity range', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(390, 2400));
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Sunny'), findsNWidgets(7));
    expect(find.textContaining('Humidity 62–85%'), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the strip scrolls sideways and fits at 390 px', (tester) async {
    await pumpApp(tester);
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SingleChildScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(position.axis, Axis.horizontal);
    expect(position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed hourly: says so, keeps the rest, Retry makes one call', (
    tester,
  ) async {
    backend.hourlyStatus = 500;
    await pumpApp(tester, size: const Size(390, 2400));
    expect(find.text("Couldn't load the hourly forecast."), findsOneWidget);
    expect(find.text('Sunny'), findsNWidgets(7), reason: 'daily is unaffected');

    final daily = backend.dailyCalls;
    final hourly = backend.hourlyCalls;
    backend.hourlyStatus = 200;
    await tester.tap(find.text('Retry'));
    await pumpFrames(tester);
    expect(backend.hourlyCalls, hourly + 1);
    expect(backend.dailyCalls, daily);
    expect(find.text("Couldn't load the hourly forecast."), findsNothing);
    expect(find.textContaining('Rain 30%'), findsWidgets);
  });

  testWidgets('no hourly periods: says not available, offers nothing false', (
    tester,
  ) async {
    backend.hourlyBody = {
      'forecast': {'periods': <Object?>[]},
    };
    await pumpApp(tester, size: const Size(390, 2400));
    expect(find.textContaining('hourly forecast'), findsOneWidget);
    expect(find.text('Sunny'), findsNWidgets(7), reason: 'daily stays');
  });

  testWidgets('hours that are over leave the strip', (tester) async {
    await pumpApp(tester, size: const Size(390, 2400));
    expect(find.textContaining('Rain 30%'), findsNWidgets(23));
    // A failed refresh keeps the old hours; those that have ended still go.
    now = now.add(const Duration(hours: 3));
    backend.dailyStatus = 500;
    await tester.pump(const Duration(minutes: 1));
    await pumpFrames(tester);
    expect(find.text('Slight Chance Light Rain'), findsNothing);
    expect(find.textContaining('Rain 30%'), findsNWidgets(21));
  });

  for (final (name, size) in const [
    ('phone-390', Size(390, 1500)),
    ('desktop-1280', Size(1280, 1150)),
  ]) {
    testWidgets('screenshot $name', (tester) async {
      await loadScreenshotFonts();
      await pumpApp(tester, size: size, realFonts: false);
      await pumpFrames(tester, frames: 8);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screens/weather-forecast/$name.png'),
      );
    }, skip: Platform.environment['SCREENSHOT_FONT_DIR'] == null);
  }
}
