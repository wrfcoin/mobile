// A location request that never answers must end, or a background run hangs
// until the system stops it.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationAccuracy;
import 'package:wrfcoin_mobile/services/location/location_service.dart';

const _channel = MethodChannel('flutter.baseflow.com/geolocator');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int permission;
  late List<String> calls;
  late Object? arguments;

  setUp(() {
    permission = 2;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call.method);
          if (call.method == 'getCurrentPosition') arguments = call.arguments;
          return switch (call.method) {
            'checkPermission' || 'requestPermission' => permission,
            'getCurrentPosition' => Completer<Object?>().future,
            _ => null,
          };
        });
  });

  testWidgets('getCurrentPosition gives up at the time limit', (tester) async {
    Object? result = 'pending';
    unawaited(LocationService().getCurrentPosition().then((p) => result = p));
    await tester.pump(LocationService.positionTimeLimit);
    await tester.pump(const Duration(seconds: 1));
    expect(result, isNull);
  });

  testWidgets('getRoughPosition gives up at the time limit', (tester) async {
    Object? result = 'pending';
    unawaited(LocationService().getRoughPosition().then((p) => result = p));
    await tester.pump(LocationService.positionTimeLimit);
    await tester.pump(const Duration(seconds: 1));
    expect(result, isNull);
  });

  for (final (name, request) in [
    ('getRoughPosition', LocationService().getRoughPosition),
    ('getQuietPosition', LocationService().getQuietPosition),
  ]) {
    testWidgets('$name asks only for low accuracy', (tester) async {
      unawaited(request());
      await tester.pump(LocationService.positionTimeLimit);
      await tester.pump(const Duration(seconds: 1));
      expect(
        (arguments as Map)['accuracy'],
        LocationAccuracy.low.index,
      );
    });
  }

  testWidgets('getQuietPosition gives up at the time limit', (tester) async {
    Object? result = 'pending';
    unawaited(LocationService().getQuietPosition().then((p) => result = p));
    await tester.pump(LocationService.positionTimeLimit);
    await tester.pump(const Duration(seconds: 1));
    expect(result, isNull);
  });

  testWidgets('getQuietPosition never shows a permission dialog', (
    tester,
  ) async {
    permission = 0;
    expect(await LocationService().getQuietPosition(), isNull);
    expect(calls, isNot(contains('requestPermission')));
    expect(calls, isNot(contains('getCurrentPosition')));
  });
}
