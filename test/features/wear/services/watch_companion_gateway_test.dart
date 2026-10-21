import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/sensor_reading_model.dart';
import 'package:wrfcoin_mobile/features/wear/domain/watch_companion_contract.dart';
import 'package:wrfcoin_mobile/features/wear/services/watch_companion_gateway.dart';

void main() {
  test('gateway records captured payloads and delegates to transport', () async {
    final captured = <WatchCompanionContract>[];
    final transport = InMemoryWatchCompanionTransport();
    final gateway = WatchCompanionGatewayOnTransport(
      transport,
      captured,
    );

    final count = await gateway.publishFromReading(
      SensorReadingModel(
        latitude: 0,
        longitude: 0,
        pressureHpa: 1009,
        timestamp: DateTime.utc(2026, 7, 30, 10),
      ),
      platform: 'watchos',
      passiveCollectionEnabled: true,
    );

    expect(count, equals(1));
    expect(captured, hasLength(1));
    expect(captured.single.toMap()['pressureHpa'], equals(1009));
    expect(transport.sent, hasLength(1));
    expect(
      transport.sent.single['platform'],
      equals('watchos'),
    );
  });

  test('noop transport remains transparent to callers', () async {
    final captured = <WatchCompanionContract>[];
    final gateway = WatchCompanionGatewayOnTransport(
      NoopWatchCompanionTransport(),
      captured,
    );

    final count = await gateway.publishFromReading(
      SensorReadingModel(
        latitude: 0,
        longitude: 0,
        pressureHpa: 1007,
        timestamp: DateTime.utc(2026, 7, 30, 10),
      ),
      platform: 'watchos',
    );

    expect(count, equals(0));
    expect(captured, hasLength(1));
  });
}
