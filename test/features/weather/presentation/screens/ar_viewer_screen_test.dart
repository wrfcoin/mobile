import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/bright_stars.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_catalog.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_sensors.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_attitude.dart';
import 'package:wrfcoin_mobile/features/sky_view/presentation/sky_map_painter.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/ar_viewer_screen.dart';

class _Sensors extends SkySensors {
  final rotation = StreamController<RotationVectorSample>.broadcast();
  @override
  Stream<RotationVectorSample> get rotationVector => rotation.stream;
}

/// #342/#341: the map draws genuine catalog objects, never decorative random
/// stars, and no camera preview exists to imply otherwise.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'every drawn object comes from the catalog, none are decorative',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('flutter.baseflow.com/geolocator');
      messenger.setMockMethodCallHandler(channel, (_) async => 1);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final sensors = _Sensors();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            skySensorsProvider.overrideWithValue(sensors),
            skyClockProvider.overrideWithValue(
              () => DateTime.utc(2026, 1, 1, 12),
            ),
          ],
          child: const MaterialApp(home: ArViewerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      SkyMapPainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<SkyMapPainter>()
          .single;

      // With no location the map draws no objects at all.
      expect(painter().fixes, isEmpty);

      await tester.tap(find.byTooltip('Location and compass'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '37.8');
      await tester.enterText(fields.at(1), '-122.4');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      sensors.rotation.add(
        const RotationVectorSample(Quat(0, 1, 0, 0), 3, -1, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final fixes = painter().fixes;
      expect(
        fixes,
        hasLength(skySources.length > 2 ? brightStars.length + 9 : 0),
      );
      final ids = {for (final star in brightStars) star.id};
      for (final fix in fixes.where((f) => !f.isSolarSystem)) {
        expect(ids, contains(fix.object.id));
      }
      expect(find.textContaining('camera preview'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await sensors.rotation.close();
    },
  );

  testWidgets('catalog licenses stay one tap from the about box', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    messenger.setMockMethodCallHandler(channel, (_) async => 1);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final sensors = _Sensors();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [skySensorsProvider.overrideWithValue(sensors)],
        child: const MaterialApp(home: ArViewerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('About this map'));
    await tester.pumpAndSettle();
    expect(find.text('Catalog licenses'), findsOneWidget);
    expect(find.textContaining('no refraction'), findsNothing);
    expect(find.textContaining('refraction is not included'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await sensors.rotation.close();
  });
}
