import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/wear/services/wear_companion_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wear payload excludes location and wallet data', () {
    final localTimestamp = DateTime(2026, 7, 29, 12);
    final payload = WearReadingPayload.fromReading(
      SensorReadingModel(
        latitude: 45.5,
        longitude: -122.6,
        pressureHpa: 1013.2,
        timestamp: localTimestamp,
      ),
    );

    expect(payload.toMap(), {
      'pressureHpa': 1013.2,
      'capturedAt': localTimestamp.toUtc().toIso8601String(),
    });
    expect(payload.toMap()['capturedAt'], endsWith('Z'));
  });

  test('bridge returns the delivery count reported by Android', () async {
    const channel = MethodChannel('test.wear');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'publishReading');
          return 1;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final count = await WearCompanionBridge(channel: channel).publishReading(
      SensorReadingModel(
        latitude: 0,
        longitude: 0,
        pressureHpa: 1000,
        timestamp: DateTime.utc(2026),
      ),
    );

    expect(count, 1);
  });
}
