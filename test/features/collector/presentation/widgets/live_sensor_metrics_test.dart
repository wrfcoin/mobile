import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/providers/sensor_stream_provider.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/widgets/live_sensor_metrics.dart';

/// Helper: pumps [LiveSensorMetrics] with a fake [sensorStreamProvider]
/// that emits the given [snapshot].
Future<void> _pumpWithSnapshot(
  WidgetTester tester,
  SensorSnapshot snapshot,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sensorStreamProvider.overrideWith(
          (ref) => Stream<SensorSnapshot>.value(snapshot),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: LiveSensorMetrics()),
        ),
      ),
    ),
  );
  // Settle the stream + AnimatedSwitcher.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('LiveSensorMetrics', () {
    testWidgets('renders temperature tile with correct value', (tester) async {
      await _pumpWithSnapshot(
        tester,
        SensorSnapshot(
          temperature: 22.5,
          humidity: 60.0,
          pressure: 1013.2,
          accelerometerMagnitude: 0.0,
          batteryLevel: 85,
          timestamp: DateTime.now(),
        ),
      );

      expect(find.text('22.5'), findsOneWidget);
    });

    testWidgets('renders humidity tile with correct value', (tester) async {
      await _pumpWithSnapshot(
        tester,
        SensorSnapshot(
          temperature: 18.0,
          humidity: 75.0,
          pressure: 1005.0,
          accelerometerMagnitude: 0.0,
          batteryLevel: 50,
          timestamp: DateTime.now(),
        ),
      );

      expect(find.text('75'), findsOneWidget);
    });

    testWidgets('renders pressure tile with correct value', (tester) async {
      await _pumpWithSnapshot(
        tester,
        SensorSnapshot(
          temperature: null,
          humidity: null,
          pressure: 1020.8,
          accelerometerMagnitude: 0.0,
          batteryLevel: 90,
          timestamp: DateTime.now(),
        ),
      );

      expect(find.text('1020.8'), findsOneWidget);
    });

    testWidgets('renders battery tile with correct value', (tester) async {
      await _pumpWithSnapshot(
        tester,
        SensorSnapshot(
          temperature: null,
          humidity: null,
          pressure: null,
          accelerometerMagnitude: 0.0,
          batteryLevel: 42,
          timestamp: DateTime.now(),
        ),
      );

      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('shows -- for null temperature', (tester) async {
      await _pumpWithSnapshot(
        tester,
        SensorSnapshot(
          temperature: null,
          humidity: null,
          pressure: null,
          accelerometerMagnitude: 0.0,
          batteryLevel: -1,
          timestamp: DateTime.now(),
        ),
      );

      // Four tiles should each show '--'
      expect(find.text('--'), findsNWidgets(4));
    });

    testWidgets('Semantics label is present for temperature tile',
        (tester) async {
      await _pumpWithSnapshot(
        tester,
        SensorSnapshot(
          temperature: 25.0,
          humidity: null,
          pressure: null,
          accelerometerMagnitude: 0.0,
          batteryLevel: 80,
          timestamp: DateTime.now(),
        ),
      );

      final semantics = tester.getSemantics(
        find.bySemanticsLabel(
          RegExp('Temperature 25.0 degrees Celsius'),
        ),
      );
      expect(semantics.label, contains('Temperature'));
    });

    testWidgets('Semantics label is present for humidity tile', (tester) async {
      await _pumpWithSnapshot(
        tester,
        SensorSnapshot(
          temperature: null,
          humidity: 65.0,
          pressure: null,
          accelerometerMagnitude: 0.0,
          batteryLevel: 70,
          timestamp: DateTime.now(),
        ),
      );

      final semantics = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Humidity 65')),
      );
      expect(semantics.label, contains('Humidity'));
    });

    testWidgets('Semantics label present for pressure tile', (tester) async {
      await _pumpWithSnapshot(
        tester,
        SensorSnapshot(
          temperature: null,
          humidity: null,
          pressure: 1015.0,
          accelerometerMagnitude: 0.0,
          batteryLevel: 60,
          timestamp: DateTime.now(),
        ),
      );

      final semantics = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Pressure 1015.0 hectopascals')),
      );
      expect(semantics.label, contains('Pressure'));
    });

    testWidgets('Semantics label present for battery tile', (tester) async {
      await _pumpWithSnapshot(
        tester,
        SensorSnapshot(
          temperature: null,
          humidity: null,
          pressure: null,
          accelerometerMagnitude: 0.0,
          batteryLevel: 55,
          timestamp: DateTime.now(),
        ),
      );

      final semantics = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Battery 55 percent')),
      );
      expect(semantics.label, contains('Battery'));
    });

    testWidgets('shows loading indicator when stream is pending',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sensorStreamProvider.overrideWith(
              // Never-emitting stream simulates "loading" state.
              (ref) => const Stream<SensorSnapshot>.empty(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: LiveSensorMetrics()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
