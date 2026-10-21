import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fakes.dart';

void main() {
  test(
    'background collection skips barometer while stationary inside interval',
    () async {
      final sensors = _FakeSensorDataSource(
        location: (lat: 37.7751, lng: -122.4191),
        pressure: 1013,
      );
      final store = FakeCollectorLocalStore(
        latestReading: SensorReading(
          id: 1,
          latitude: 37.775,
          longitude: -122.419,
          pressureHpa: 1012,
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          synced: false,
        ),
      );
      final repository = CollectorRepository(
        sensorDataSource: sensors,
        batteryMonitor: FakeBatteryMonitor(batteryLevel: 80),
        apiClient: ApiClient(dio: Dio()),
        db: store,
      );

      final result = await repository.collectReading(baseIntervalMinutes: 15);

      expect(result.isSuccess, isFalse);
      expect(
        result.failureReason,
        CollectReadingFailureReason.stationaryBackoff,
      );
      expect(sensors.barometerReadCount, 0);
      expect(store.insertCalls, 0);
    },
  );

  test('manual collection can force a reading at the same location', () async {
    final sensors = _FakeSensorDataSource(
      location: (lat: 37.7751, lng: -122.4191),
      pressure: 1013,
    );
    final store = FakeCollectorLocalStore(
      latestReading: SensorReading(
        id: 1,
        latitude: 37.775,
        longitude: -122.419,
        pressureHpa: 1012,
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        synced: false,
      ),
    );
    final repository = CollectorRepository(
      sensorDataSource: sensors,
      batteryMonitor: FakeBatteryMonitor(batteryLevel: 80),
      apiClient: ApiClient(dio: Dio()),
      db: store,
    );

    final result = await repository.collectReading(force: true);

    expect(result.isSuccess, isTrue);
    expect(sensors.barometerReadCount, 1);
    expect(store.insertCalls, 1);
  });
}

class _FakeSensorDataSource extends SensorDataSource {
  _FakeSensorDataSource({required this.location, required this.pressure})
    : super(LocationService());

  final ({double lat, double lng})? location;
  final double? pressure;
  int barometerReadCount = 0;

  @override
  Future<({double lat, double lng})?> readLocation() async => location;

  @override
  Future<double?> readBarometer() async {
    barometerReadCount++;
    return pressure;
  }
}
