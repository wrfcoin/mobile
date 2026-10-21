import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_sensors.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/catalog_license.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/ar_viewer_screen.dart';

class _Sensors extends SkySensors {
  final g = StreamController<List<double>>.broadcast();
  final m = StreamController<List<double>>.broadcast();
  @override
  Stream<List<double>> get gravity => g.stream;
  @override
  Stream<List<double>> get magnetic => m.stream;
}

class _NoHttp extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    calls++;
    throw StateError('Sky View must stay offline');
  }
}

class _Resolver extends WeatherLocationResolver {
  final pending = Completer<WeatherLocationResult>();
  @override
  Future<WeatherLocationResult> resolve() => pending.future;
}

Future<void> _settings(
  WidgetTester tester, {
  String latitude = '-16.743',
  String longitude = '-179.234',
  String declination = '0',
}) async {
  await tester.tap(find.text('Set offline sky settings'));
  await tester.pumpAndSettle();
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), latitude);
  await tester.enterText(fields.at(1), longitude);
  await tester.enterText(fields.at(2), declination);
  await tester.tap(find.text('Use cell'));
  await tester.pumpAndSettle();
}

void main() {
  late _Sensors sensors;
  late _NoHttp noHttp;
  late DateTime now;
  setUp(() {
    sensors = _Sensors();
    now = DateTime.utc(2000, 1, 1, 12);
    noHttp = _NoHttp();
    HttpOverrides.global = noHttp;
  });
  tearDown(() async {
    HttpOverrides.global = null;
    await sensors.g.close();
    await sensors.m.close();
  });
  test(
    'complete catalog notice ships through the application license registry',
    () async {
      registerSkyCatalogLicense();
      final entries = await LicenseRegistry.licenses
          .where(
            (entry) => entry.packages.contains('Yale BSC5 bright-star subset'),
          )
          .toList();
      expect(entries, hasLength(1));
      final notice = entries.single.paragraphs.map((p) => p.text).join('\n');
      expect(notice, contains('Copyright (c) 2016 Bretton Wade'));
      expect(notice, contains('Permission is hereby granted'));
      expect(notice, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
    },
  );
  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        skySensorsProvider.overrideWithValue(sensors),
        skyClockProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: ArViewerScreen()),
    ),
  );

  testWidgets(
    'existing route starts offline, without fabricated default direction',
    (tester) async {
      await mount(tester);
      await tester.pumpAndSettle();
      expect(find.text('Sky View'), findsOneWidget);
      expect(find.textContaining('Choose a coarse location'), findsOneWidget);
      expect(find.textContaining('True azimuth'), findsNothing);
      expect(find.text('Sirius'), findsNothing);
      expect(noHttp.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('real Sirius identification, quantization, details and no HTTP', (
    tester,
  ) async {
    await mount(tester);
    await _settings(tester);
    sensors.g.add([0, 0, -9.8]);
    sensors.m.add([0, 30, 40]);
    await tester.pumpAndSettle();
    expect(find.text('Sirius'), findsOneWidget);
    expect(find.textContaining('Coarse cell: -16.7,-179.2'), findsOneWidget);
    expect(find.textContaining('-16.743'), findsNothing);
    expect(find.textContaining('-179.234'), findsNothing);
    await tester.ensureVisible(find.text('Sirius'));
    await tester.tap(find.text('Sirius'));
    await tester.pumpAndSettle();
    expect(find.textContaining('HR2491'), findsOneWidget);
    expect(
      find.textContaining('Approximate geometric rise/set — next 24h'),
      findsOneWidget,
    );
    expect(find.textContaining('Rise:'), findsOneWidget);
    expect(find.textContaining('Set:'), findsOneWidget);
    expect(find.textContaining('UTC'), findsOneWidget);
    expect(noHttp.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'one sensor, invalid samples and stale samples never label an object',
    (tester) async {
      await mount(tester);
      await _settings(tester);
      sensors.g.add([0, 0, -9.8]);
      await tester.pumpAndSettle();
      expect(find.text('Sirius'), findsNothing);
      sensors.m.add([0, 0, 0]);
      await tester.pumpAndSettle();
      expect(find.text('Sirius'), findsNothing);
      sensors.m.add([0, 30, 40]);
      await tester.pumpAndSettle();
      expect(find.text('Sirius'), findsOneWidget);
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Sirius'), findsNothing);
      expect(find.textContaining('True azimuth'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'pause cancels subscriptions; resume needs fresh samples; dispose cancels timers',
    (tester) async {
      await mount(tester);
      await _settings(tester);
      sensors.g.add([0, 0, -9.8]);
      sensors.m.add([0, 30, 40]);
      await tester.pumpAndSettle();
      expect(sensors.g.hasListener, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(sensors.g.hasListener, isFalse);
      expect(sensors.m.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(sensors.g.hasListener, isTrue);
      expect(find.text('Sirius'), findsNothing);
      sensors.g.add([0, 0, -9.8]);
      sensors.m.add([0, 30, 40]);
      await tester.pumpAndSettle();
      expect(find.text('Sirius'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(sensors.g.hasListener, isFalse);
      expect(sensors.m.hasListener, isFalse);
    },
  );
  testWidgets(
    'invalid settings and unsupported epoch do not fabricate positions',
    (tester) async {
      await mount(tester);
      await _settings(tester, latitude: 'NaN');
      expect(find.textContaining('Enter finite latitude'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      now = DateTime.utc(2051);
      await _settings(tester);
      sensors.g.add([0, 0, -9.8]);
      sensors.m.add([0, 30, 40]);
      await tester.pumpAndSettle();
      expect(find.text('Sirius'), findsNothing);
      expect(find.textContaining('outside 1800–2050'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('denied device permission leaves no cell or HTTP request', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => call.method == 'isLocationServiceEnabled' ? true : 0,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'),
            null,
          ),
    );
    await mount(tester);
    await tester.tap(find.text('Use device location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Location unavailable'), findsOneWidget);
    expect(find.textContaining('Coarse cell:'), findsNothing);
    expect(noHttp.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'device result after pause is discarded and requires a new read',
    (tester) async {
      final resolver = _Resolver();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'),
            (_) async => 2,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('flutter.baseflow.com/geolocator'),
              null,
            ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            skySensorsProvider.overrideWithValue(sensors),
            skyClockProvider.overrideWithValue(() => now),
            weatherLocationResolverProvider.overrideWithValue(resolver),
          ],
          child: const MaterialApp(home: ArViewerScreen()),
        ),
      );
      await tester.tap(find.text('Use device location'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      resolver.pending.complete(
        WeatherLocationResult.located(CoarseLocation.round(12.345, 23.456)),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Coarse cell:'), findsNothing);
      expect(find.textContaining('Choose a coarse location'), findsOneWidget);
      expect(noHttp.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
