import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/data/sky_sensors.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/ar_viewer_screen.dart';

/// #342/#341: a schematic sky may label genuine catalog objects, never
/// decorative random stars or a camera preview that does not exist.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Make the motion sensors "available" (silent streams) so the sky view,
    // not the sensors-unavailable fallback, is what renders.
    for (final name in ['magnetometer', 'accelerometer']) {
      final channel = MethodChannel('dev.fluttercommunity.plus/sensors/$name');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  testWidgets('draws no decorative stars and labels the schematic sky', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          skyClockProvider.overrideWithValue(
            () => DateTime.utc(2000, 1, 1, 12),
          ),
        ],
        child: const MaterialApp(home: ArViewerScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Motion sensors unavailable'), findsNothing);
    expect(find.text('Offline sky — not a camera preview'), findsOneWidget);

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter?.runtimeType.toString())
        .whereType<String>();
    expect(painters, isNot(contains('_SkyPainter')));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
