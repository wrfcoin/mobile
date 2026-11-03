// The rough cell: low accuracy, a time limit, rounded before it is returned.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationAccuracy;
import 'package:wrfcoin_mobile/services/location/location_service.dart';

const _channel = MethodChannel('flutter.baseflow.com/geolocator');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Object? arguments;
  late bool hang;

  setUp(() {
    arguments = null;
    hang = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'checkPermission' || 'requestPermission':
              return 2;
            case 'getCurrentPosition':
              arguments = call.arguments;
              if (hang) return Completer<Object?>().future;
              return <String, Object?>{
                'latitude': 46.78312,
                'longitude': -92.10654,
                'timestamp': DateTime.utc(2026, 11, 2).millisecondsSinceEpoch,
                'accuracy': 25.0,
                'altitude': 0.0,
                'heading': 0.0,
                'speed': 0.0,
                'speed_accuracy': 0.0,
              };
          }
          return null;
        });
  });

  test('asks for low accuracy and returns only the 0.1 degree cell', () async {
    final cell = await LocationService().getRoughCell();
    expect(cell, (lat: 46.8, lng: -92.1));
    expect((arguments as Map)['accuracy'], LocationAccuracy.low.index);
  });

  testWidgets('gives up at 20 seconds', (tester) async {
    hang = true;
    Object? result = 'pending';
    unawaited(LocationService().getRoughCell().then((c) => result = c));
    await tester.pump(const Duration(seconds: 21));
    expect(result, isNull);
  });
}
