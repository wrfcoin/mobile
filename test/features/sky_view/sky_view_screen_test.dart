import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/catalog_license.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_sensors.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_attitude.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_projection.dart';
import 'package:wrfcoin_mobile/features/sky_view/presentation/sky_map_painter.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/ar_viewer_screen.dart';

class _Sensors extends SkySensors {
  final rotation = StreamController<RotationVectorSample>.broadcast();
  final g = StreamController<List<double>>.broadcast();
  final m = StreamController<List<double>>.broadcast();
  @override
  Stream<RotationVectorSample> get rotationVector => rotation.stream;
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
  _Resolver(this.results);
  final List<Future<WeatherLocationResult>> results;
  int reads = 0;
  @override
  Future<WeatherLocationResult> resolve() => results[reads++];
}

const _geolocator = MethodChannel('flutter.baseflow.com/geolocator');

/// Geolocator's channel. Permission values are LocationPermission's indexes:
/// 0 denied, 1 deniedForever, 2 whileInUse.
void _mockPermission(WidgetTester tester, int check, {int? onRequest}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_geolocator, (call) async {
    if (call.method == 'checkPermission') return check;
    if (call.method == 'requestPermission') return onRequest ?? check;
    if (call.method == 'isLocationServiceEnabled') return true;
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_geolocator, null));
}

const _phoneFaceDown = Quat(0, 1, 0, 0); // Back of the phone straight up.

RotationVectorSample _fused(
  Quat attitude, {
  int status = 3,
  double heading = -1,
  int display = 0,
}) => RotationVectorSample(attitude, status, heading, display);

void main() {
  late _Sensors sensors;
  late _NoHttp noHttp;
  late DateTime now;
  // A real cell, a date inside WMM2025, and a star near the zenith there.
  const latitude = -16.743, longitude = -179.234;

  setUp(() {
    sensors = _Sensors();
    now = DateTime.utc(2026, 1, 1, 12);
    noHttp = _NoHttp();
    HttpOverrides.global = noHttp;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    HttpOverrides.global = null;
    await sensors.rotation.close();
    await sensors.g.close();
    await sensors.m.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    WeatherLocationResolver? resolver,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          skySensorsProvider.overrideWithValue(sensors),
          skyClockProvider.overrideWithValue(() => now),
          if (resolver != null)
            weatherLocationResolverProvider.overrideWithValue(resolver),
        ],
        child: const MaterialApp(home: ArViewerScreen()),
      ),
    );
    await tester.pump();
  }

  /// Types a location through the settings dialog.
  Future<void> enterLocation(
    WidgetTester tester, {
    String lat = '$latitude',
    String lon = '$longitude',
    String declination = '',
  }) async {
    await tester.tap(find.byTooltip('Location and compass'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), lat);
    await tester.enterText(fields.at(1), lon);
    await tester.enterText(fields.at(2), declination);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  /// Points the phone straight up and lets the map settle, for a known sky.
  Future<void> pointUp(WidgetTester tester) async {
    sensors.rotation.add(_fused(_phoneFaceDown));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  SkyMapPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<SkyMapPainter>()
      .single;

  double readableAzimuth(WidgetTester tester) =>
      painter(tester).pose.value!.boresight.azimuth;

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

  group('offline and honest', () {
    testWidgets('opens with no fabricated direction, sky or HTTP', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      expect(find.text('Sky View'), findsOneWidget);
      expect(find.textContaining('Facing'), findsNothing);
      expect(painter(tester).fixes, isEmpty);
      expect(noHttp.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('identifies a real star, shows details, and makes no HTTP', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      await enterLocation(tester);
      await pointUp(tester);
      expect(painter(tester).fixes, isNotEmpty);
      final near = tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((c) => ((c.label) as Text).data!)
          .toList();
      expect(near, isNotEmpty);
      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('no atmospheric refraction'), findsOneWidget);
      expect(find.textContaining('Rise:'), findsOneWidget);
      expect(find.textContaining('UTC'), findsOneWidget);
      expect(noHttp.calls, 0);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('tapping the map opens the object under the finger', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      await enterLocation(tester);
      await pointUp(tester);
      final map = painter(tester);
      final screen = tester.getSize(find.byType(Scaffold));
      final projection = SkyProjection(map.pose.value!, screen);
      // Something in the top half of the screen, clear of the status panel, and
      // with no other object close enough to take the tap.
      final onScreen = [
        for (final fix in map.fixes)
          if (projection.project(fix.direction) case final at?)
            if (at.dx > 40 &&
                at.dx < screen.width - 40 &&
                at.dy > 100 &&
                at.dy < screen.height / 2)
              (fix, at),
      ];
      expect(onScreen, isNotEmpty);
      final (target, at) = onScreen.first;
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      final expected = skyObjectAt(at, map.fixes, map.pose.value!, screen);
      expect(expected?.object.id, target.object.id);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(target.object.name),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'a stale sensor removes the direction rather than freezing it',
      (tester) async {
        _mockPermission(tester, 1);
        await mount(tester);
        await tester.pumpAndSettle();
        await enterLocation(tester);
        await pointUp(tester);
        expect(find.textContaining('straight up'), findsOneWidget);
        now = now.add(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.textContaining('straight up'), findsNothing);
        expect(
          find.textContaining('Waiting for the motion sensors'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('dates past the ephemeris show no positions', (tester) async {
      _mockPermission(tester, 1);
      now = DateTime.utc(2051);
      await mount(tester);
      await tester.pumpAndSettle();
      await enterLocation(tester);
      await pointUp(tester);
      expect(painter(tester).fixes, isEmpty);
      expect(find.textContaining('outside 1800–2050'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('invalid settings are refused with a plain message', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      await enterLocation(tester, lat: 'NaN');
      expect(find.textContaining('Enter finite latitude'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('sensors', () {
    testWidgets('fused sensor drives the map; the fallback stays off', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      await pointUp(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(sensors.rotation.hasListener, isTrue);
      expect(sensors.g.hasListener, isFalse);
      expect(sensors.m.hasListener, isFalse);
      expect(find.textContaining('less steady'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('no sensor: falls back, and tells the user it is less steady', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      sensors.rotation.addError(
        PlatformException(code: 'unavailable', message: 'none'),
      );
      await tester.pump();
      expect(sensors.g.hasListener, isTrue);
      expect(sensors.m.hasListener, isTrue);
      sensors.g.add([0, 0, -9.8]);
      sensors.m.add([0, 30, 40]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('less steady'), findsOneWidget);
      expect(find.textContaining('straight up'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(sensors.g.hasListener, isFalse);
    });

    testWidgets('a sensor that stays silent also falls back', (tester) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      expect(sensors.g.hasListener, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(sensors.g.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('one fallback sensor alone, or bad data, draws nothing', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      sensors.rotation.addError('none');
      await tester.pump();
      sensors.g.add([0, 0, -9.8]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('straight up'), findsNothing);
      sensors.m.add([0, 0, 0]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('straight up'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'backgrounding stops sensors; coming back needs fresh samples',
      (tester) async {
        _mockPermission(tester, 1);
        await mount(tester);
        await tester.pumpAndSettle();
        await pointUp(tester);
        expect(sensors.rotation.hasListener, isTrue);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(sensors.rotation.hasListener, isFalse);
        expect(painter(tester).pose.value, isNull);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(sensors.rotation.hasListener, isTrue);
        expect(find.textContaining('straight up'), findsNothing);
        await pointUp(tester);
        expect(find.textContaining('straight up'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(sensors.rotation.hasListener, isFalse);
      },
    );

    testWidgets('a fallback session restarts its sensors after backgrounding', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      sensors.rotation.addError('none');
      await tester.pump();
      expect(sensors.g.hasListener, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(sensors.g.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      sensors.rotation.addError('none');
      await tester.pump();
      expect(sensors.g.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the notification shade does not stop the sensors', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      await pointUp(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(sensors.rotation.hasListener, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a resting phone stops redrawing', (tester) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      await pointUp(tester);
      final map = painter(tester);
      var repaints = 0;
      map.pose.addListener(() => repaints++);
      // Noise far below a pixel, at the sensor's rate.
      for (var i = 0; i < 30; i++) {
        sensors.rotation.add(_fused(_phoneFaceDown));
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(repaints, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('calibration words', () {
    testWidgets('good accuracy reads good and does not prompt', (tester) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      sensors.rotation.add(_fused(_phoneFaceDown, status: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Compass: good'), findsOneWidget);
      expect(find.textContaining('figure-eight'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('low accuracy reads poor, prompts, and can be hidden', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      sensors.rotation.add(_fused(_phoneFaceDown, status: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Compass: poor'), findsOneWidget);
      expect(find.textContaining('figure-eight'), findsOneWidget);
      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.textContaining('figure-eight'), findsNothing);
      expect(find.textContaining('Compass: poor'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('accuracy recovery removes the prompt', (tester) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      sensors.rotation.add(_fused(_phoneFaceDown, status: 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('figure-eight'), findsOneWidget);
      sensors.rotation.add(_fused(_phoneFaceDown, status: 3));
      await tester.pump();
      expect(find.textContaining('figure-eight'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('declination', () {
    // Upright, the back of the phone at magnetic north, tilted up 20 degrees.
    final atMagneticNorth = () {
      final h = 110 * math.pi / 360;
      return Quat(math.cos(h), math.sin(h), 0, 0);
    }();

    testWidgets('is automatic once the location is known, with nothing typed', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      // San Francisco area: official WMM2025 declination is about 13 degrees
      // east at this date (see wmm_test.dart for the checked table).
      await enterLocation(tester, lat: '37.8', lon: '-122.4');
      sensors.rotation.add(_fused(atMagneticNorth));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(readableAzimuth(tester), closeTo(13, 1));
      expect(find.textContaining('true north'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'manual override replaces the automatic value, not adds to it',
      (tester) async {
        _mockPermission(tester, 1);
        await mount(tester);
        await tester.pumpAndSettle();
        await enterLocation(
          tester,
          lat: '37.8',
          lon: '-122.4',
          declination: '5',
        );
        sensors.rotation.add(_fused(atMagneticNorth));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(readableAzimuth(tester), closeTo(5, 1e-3));
        // Clearing it goes back to automatic.
        await enterLocation(tester, lat: '37.8', lon: '-122.4');
        await tester.pump();
        expect(readableAzimuth(tester), closeTo(13, 1));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('past the model\'s dates it says magnetic, uncorrected', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      now = DateTime.utc(2031);
      await mount(tester);
      await tester.pumpAndSettle();
      await enterLocation(tester, lat: '37.8', lon: '-122.4');
      sensors.rotation.add(_fused(atMagneticNorth));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.textContaining('magnetic north, uncorrected'),
        findsOneWidget,
      );
      expect(readableAzimuth(tester) % 360, closeTo(0, 1e-3));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('align on a star', () {
    Future<void> aligned(WidgetTester tester) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      await enterLocation(tester, lat: '37.8', lon: '-122.4', declination: '0');
      // Any first reading, so the sky is computed; then aim near a real object.
      sensors.rotation.add(_fused(_phoneFaceDown));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final target = painter(tester).fixes.firstWhere(
        (f) => f.horizontal.altitude > 30 && f.horizontal.altitude < 60,
      );
      final az = (target.horizontal.azimuth + 4) * math.pi / 360;
      final alt = (90 + target.horizontal.altitude + 2) * math.pi / 360;
      // Turn about the vertical (clockwise from above) after tilting up.
      final q = Quat(
        math.cos(az) * math.cos(alt),
        math.cos(az) * math.sin(alt),
        -math.sin(az) * math.sin(alt),
        -math.sin(az) * math.cos(alt),
      );
      sensors.rotation.add(_fused(q));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('stores a small offset that centres the object, and resets', (
      tester,
    ) async {
      await aligned(tester);
      final map = painter(tester);
      final before = map.pose.value!.boresight;
      await tester.tap(find.text('Align on a star'));
      await tester.pump();
      expect(find.textContaining('Aim the back of the phone'), findsOneWidget);
      await tester.tap(find.byType(ActionChip).first);
      await tester.pump();
      expect(find.textContaining('Aligned on'), findsOneWidget);
      expect(find.text('Reset alignment'), findsOneWidget);
      final after = map.pose.value!.boresight;
      expect(after.azimuth, isNot(closeTo(before.azimuth, 0.01)));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('sky_view.align_azimuth'), isNotNull);

      await tester.tap(find.text('Reset alignment'));
      await tester.pump();
      final reset = map.pose.value!.boresight;
      expect(reset.azimuth, closeTo(before.azimuth, 1e-6));
      expect(find.text('Reset alignment'), findsNothing);
      expect(prefs.getDouble('sky_view.align_azimuth'), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a stored offset is applied on the next open', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sky_view.align_azimuth': 3.0,
        'sky_view.align_altitude': 0.0,
      });
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      await enterLocation(tester, lat: '37.8', lon: '-122.4', declination: '0');
      final h = 110 * math.pi / 360;
      sensors.rotation.add(_fused(Quat(math.cos(h), math.sin(h), 0, 0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(readableAzimuth(tester), closeTo(3, 1e-3));
      expect(find.textContaining('aligned'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('location', () {
    testWidgets('already allowed: reads on open with no dialog', (
      tester,
    ) async {
      _mockPermission(tester, 2);
      final resolver = _Resolver([
        Future.value(
          WeatherLocationResult.located(CoarseLocation.round(12.345, 23.456)),
        ),
      ]);
      await mount(tester, resolver: resolver);
      await tester.pumpAndSettle();
      expect(resolver.reads, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(painter(tester).fixes, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('asks with a one-line reason, then asks Android', (
      tester,
    ) async {
      _mockPermission(tester, 0, onRequest: 2);
      final resolver = _Resolver([
        Future.value(
          WeatherLocationResult.located(CoarseLocation.round(12.345, 23.456)),
        ),
      ]);
      await mount(tester, resolver: resolver);
      await tester.pumpAndSettle();
      expect(find.textContaining('stays on this phone'), findsOneWidget);
      expect(resolver.reads, 0);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(resolver.reads, 1);
      expect(painter(tester).fixes, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('choosing not to share gets manual entry, no read, no HTTP', (
      tester,
    ) async {
      _mockPermission(tester, 0);
      final resolver = _Resolver(const []);
      await mount(tester, resolver: resolver);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter it myself'));
      await tester.pumpAndSettle();
      expect(resolver.reads, 0);
      expect(find.text('Enter location'), findsOneWidget);
      expect(noHttp.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('refused by Android: plain manual entry fallback', (
      tester,
    ) async {
      _mockPermission(tester, 0, onRequest: 0);
      await mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Enter location'), findsOneWidget);
      expect(painter(tester).fixes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('blocked for good: offers settings as well as manual entry', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      expect(find.text('Enter location'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the exact fix never appears, only the 0.1° cell', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pumpAndSettle();
      await enterLocation(tester);
      await tester.tap(find.byTooltip('Location and compass'));
      await tester.pumpAndSettle();
      expect(find.text('-16.7'), findsOneWidget);
      expect(find.text('-179.2'), findsOneWidget);
      expect(find.textContaining('-16.743'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'a result arriving after backgrounding is thrown away and read again',
      (tester) async {
        _mockPermission(tester, 2);
        final first = Completer<WeatherLocationResult>();
        final second = Completer<WeatherLocationResult>();
        final resolver = _Resolver([first.future, second.future]);
        await mount(tester, resolver: resolver);
        await tester.pump();
        await tester.pump();
        expect(resolver.reads, 1);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        first.complete(
          WeatherLocationResult.located(CoarseLocation.round(12.345, 23.456)),
        );
        await tester.pump();
        expect(painter(tester).fixes, isEmpty);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(resolver.reads, 2);
        second.complete(
          WeatherLocationResult.located(CoarseLocation.round(40.1, -74.2)),
        );
        await tester.pump();
        await tester.pump();
        expect(painter(tester).fixes, isNotEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('a typed location survives backgrounding, with no new read', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      final resolver = _Resolver(const []);
      await mount(tester, resolver: resolver);
      await tester.pumpAndSettle();
      await enterLocation(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(resolver.reads, 0);
      await pointUp(tester);
      expect(painter(tester).fixes, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('layout', () {
    for (final (name, size) in const [
      ('phone', Size(390, 844)),
      ('small phone', Size(320, 568)),
      ('landscape phone', Size(844, 390)),
      ('desktop', Size(1280, 800)),
    ]) {
      testWidgets('fits a $name with no overflow, and in every state', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        _mockPermission(tester, 1);
        await mount(tester);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await enterLocation(tester);
        sensors.rotation.add(_fused(_phoneFaceDown, status: 1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Align on a star'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('the map fills the whole screen, under the status panel', (
      tester,
    ) async {
      _mockPermission(tester, 1);
      await mount(tester);
      await tester.pump();
      final painted = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((p) => p.painter is SkyMapPainter);
      expect(painted.size, Size.infinite);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
