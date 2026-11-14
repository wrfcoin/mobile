// The welcome check: a phone says whether it has a barometer, and only a
// definite "no sensor" counts as no.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';

const _events = EventChannel('dev.fluttercommunity.plus/sensors/barometer');
const _method = MethodChannel('dev.fluttercommunity.plus/sensors/method');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // The plugin keeps one barometer stream for the process, so each case
  // changes what the channel answers, not the stream.
  late void Function(MockStreamHandlerEventSink sink) answer;

  setUpAll(() {
    messenger.setMockMethodCallHandler(_method, (_) async => null);
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(onListen: (_, sink) => answer(sink)),
    );
  });
  tearDownAll(() {
    messenger.setMockMethodCallHandler(_method, null);
    messenger.setMockStreamHandler(_events, null);
  });

  Future<bool?> probe() => SensorDataSource(LocationService()).hasBarometer();

  test('a reading: it has one', () async {
    answer = (sink) => sink.success(<double>[1013.2, 1.0e15]);
    expect(await probe(), isTrue);
  });

  test('NO_SENSOR: it has none', () async {
    answer = (sink) => sink.error(code: 'NO_SENSOR', message: 'none');
    expect(await probe(), isFalse);
  });

  test('any other error: it cannot tell', () async {
    answer = (sink) => sink.error(code: 'SOMETHING_ELSE');
    expect(await probe(), isNull);
  });
}
