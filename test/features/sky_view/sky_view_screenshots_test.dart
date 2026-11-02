// Renders the PR screenshots. Skipped by default, because text rendering differs
// per platform. To regenerate:
//   flutter test --update-goldens --dart-define=SKY_SCREENSHOTS=true \
//     test/features/sky_view/sky_view_screenshots_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_sensors.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_attitude.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/ar_viewer_screen.dart';

const _enabled = bool.fromEnvironment('SKY_SCREENSHOTS');

class _Sensors extends SkySensors {
  final rotation = StreamController<RotationVectorSample>.broadcast();
  @override
  Stream<RotationVectorSample> get rotationVector => rotation.stream;
}

class _Resolver extends WeatherLocationResolver {
  @override
  Future<WeatherLocationResult> resolve() async =>
      WeatherLocationResult.located(CoarseLocation.round(37.8, -122.4));
}

Future<void> _loadRoboto() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '/home/tony/flutter';
  final loader = FontLoader('Roboto')
    ..addFont(
      File('$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)),
    );
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then((b) => ByteData.sublistView(b)),
    );
  await icons.load();
}

void main() {
  for (final (name, size) in const [
    ('phone-390', Size(390, 844)),
    ('desktop-1280', Size(1280, 800)),
  ]) {
    testWidgets('sky view $name', skip: !_enabled, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(_loadRoboto);
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel('flutter.baseflow.com/geolocator');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => 2);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final sensors = _Sensors();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            skySensorsProvider.overrideWithValue(sensors),
            // An evening with Orion and Sirius rising in the southeast.
            skyClockProvider.overrideWithValue(
              () => DateTime.utc(2027, 1, 15, 5),
            ),
            weatherLocationResolverProvider.overrideWithValue(_Resolver()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
            home: const ArViewerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Upright, tilted 35 degrees up, facing south-southeast (true 165).
      final az = -(165 - 13.2) * math.pi / 360;
      final alt = (90 + 35) * math.pi / 360;
      sensors.rotation.add(
        RotationVectorSample(
          Quat(
            math.cos(az) * math.cos(alt),
            math.cos(az) * math.sin(alt),
            math.sin(az) * math.sin(alt),
            math.sin(az) * math.cos(alt),
          ),
          3,
          -1,
          0,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await expectLater(
        find.byType(ArViewerScreen),
        matchesGoldenFile('../../../docs/screenshots/sky-view/$name.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await sensors.rotation.close();
    });
  }
}
