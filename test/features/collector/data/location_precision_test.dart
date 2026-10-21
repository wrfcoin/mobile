// Collect readings carry location at 0.1 degree (~11 km) only (owner ruling 2026-09-30):
// on capture, on submission (including readings queued earlier at 3 decimals), in history and on
// screen. Synthetic coordinates only.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/datasources/sensor_data_source.dart';
import 'package:wrfcoin_mobile/features/collector/data/repositories/collector_repository_impl.dart';
import 'package:wrfcoin_mobile/features/collector/domain/cloud_observation.dart';
import 'package:wrfcoin_mobile/features/collector/domain/imagery_submission_payload.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/crypto/collect_key_store.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../../test_helpers/fake_station_backend.dart';
import '../../../test_helpers/fakes.dart';

class _Capture extends Interceptor {
  final bodies = <Map<String, dynamic>>[];
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final prepared = answerPrepare(options);
    if (prepared != null) {
      handler.resolve(prepared);
      return;
    }
    if (options.data is Map<String, dynamic>) {
      bodies.add(Map<String, dynamic>.from(options.data as Map<String, dynamic>));
    }
    handler.resolve(Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 200,
      data: <String, dynamic>{'success': true, 'submissionId': 'sub-1'},
    ));
  }
}

SensorReading _row(double lat, double lng) => SensorReading(
  id: 1,
  latitude: lat,
  longitude: lng,
  pressureHpa: 1013.25,
  timestamp: DateTime.utc(2026, 9, 30, 12),
  synced: false,
);

class _FineFixSource extends SensorDataSource {
  _FineFixSource() : super(LocationService());
  @override
  Future<({double lat, double lng})?> readLocation() async => (lat: 10.12349, lng: 20.45678);
  @override
  Future<double?> readBarometer() async => 1013.0;
}

/// Number of digits after the decimal point in the shortest round-trip text of [v].
int _decimals(num v) {
  final text = v.toString();
  final dot = text.indexOf('.');
  return dot < 0 ? 0 : text.length - dot - 1;
}

void main() {
  late CollectKey key;
  setUpAll(() async {
    key = await syntheticCollectKey();
  });

  group('LocationService.anonymize is the 0.1 degree grid', () {
    test('rounds to one decimal', () {
      expect(LocationService.anonymize(10.12349), 10.1);
      expect(LocationService.anonymize(20.45678), 20.5);
      expect(LocationService.anonymize(-10.04), -10.0);
    });
    test('no negative zero: the sign of a zero would say which half of the cell', () {
      expect(LocationService.anonymize(-0.04).toString(), '0.0');
    });
    test('poles and antimeridian stay in range', () {
      expect(LocationService.anonymize(89.96), 90.0);
      expect(LocationService.anonymize(-179.96), -180.0);
    });
  });

  group('submission payload', () {
    test('a reading queued at 3 decimals is coarsened to 0.1 before it is sent', () async {
      final capture = _Capture();
      final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))..interceptors.add(capture);
      final repo = CollectorRepository(
        sensorDataSource: FakeCollectorRepository().sensorDataSource,
        batteryMonitor: FakeBatteryMonitor(),
        apiClient: ApiClient(dio: dio, allowUnauthenticatedRequests: true),
        db: FakeCollectorLocalStore(),
      );
      await repo.submitBatch([_row(10.123, 20.456)], walletAddress: 'wrf1testaddr', signer: key);
      expect(capture.bodies, hasLength(1));
      final location = capture.bodies.single['location'] as Map;
      expect(location['latitude'], 10.1);
      expect(location['longitude'], 20.5);
      expect(_decimals(location['latitude'] as num), lessThanOrEqualTo(1));
      expect(_decimals(location['longitude'] as num), lessThanOrEqualTo(1));
    });

    test('an already-coarse reading is unchanged', () async {
      final capture = _Capture();
      final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))..interceptors.add(capture);
      final repo = CollectorRepository(
        sensorDataSource: FakeCollectorRepository().sensorDataSource,
        batteryMonitor: FakeBatteryMonitor(),
        apiClient: ApiClient(dio: dio, allowUnauthenticatedRequests: true),
        db: FakeCollectorLocalStore(),
      );
      await repo.submitBatch([_row(10.0, 20.0)], walletAddress: 'wrf1testaddr', signer: key);
      final location = capture.bodies.single['location'] as Map;
      expect(location['latitude'], 10.0);
      expect(location['longitude'], 20.0);
    });
  });

  group('imagery payload', () {
    test('coordinates are coarsened to 0.1 whatever the caller passes', () {
      final payload = buildImagerySubmissionPayload(
        category: 'cloud_formation',
        cloudGenus: CloudGenus.values.first,
        description: 'd',
        latitude: 10.123,
        longitude: 20.456,
      );
      expect(payload['latitude'], 10.1);
      expect(payload['longitude'], 20.5);
    });
    test('no location stays absent', () {
      final payload = buildImagerySubmissionPayload(
        category: 'other',
        cloudGenus: CloudGenus.values.first,
        description: 'd',
      );
      expect(payload.containsKey('latitude'), isFalse);
      expect(payload.containsKey('longitude'), isFalse);
    });
  });

  group('capture', () {
    test('a source that returns a fine fix is still stored and returned at 0.1', () async {
      final repo = CollectorRepository(
        sensorDataSource: _FineFixSource(),
        batteryMonitor: FakeBatteryMonitor(batteryLevel: 80),
        apiClient: ApiClient(dio: Dio(), allowUnauthenticatedRequests: true),
        db: FakeCollectorLocalStore(),
      );
      final result = await repo.collectReading(baseIntervalMinutes: 15, force: true);
      expect(result.isSuccess, isTrue);
      expect(result.reading!.latitude, 10.1);
      expect(result.reading!.longitude, 20.5);
    });
  });

  group('history read from the device', () {
    test('a stored 3-decimal reading is served at 0.1', () async {
      final repo = CollectorRepository(
        sensorDataSource: FakeCollectorRepository().sensorDataSource,
        batteryMonitor: FakeBatteryMonitor(),
        apiClient: ApiClient(dio: Dio(), allowUnauthenticatedRequests: true),
        db: FakeCollectorLocalStore(latestReading: _row(10.123, 20.456)),
      );
      final history = await repo.getReadingHistory();
      expect(history.single.latitude, 10.1);
      expect(history.single.longitude, 20.5);
    });
  });

  group('no screen, log or message prints a reading position finer than 0.1', () {
    test('no toStringAsFixed(2+) on a latitude or longitude in the collect or imagery code', () {
      final offenders = <String>[];
      for (final path in [
        'lib/features/collector/presentation/screens/collector_dashboard.dart',
        'lib/features/collector/presentation/screens/imagery_upload_screen.dart',
        'lib/features/collector/presentation/providers/collector_provider.dart',
      ]) {
        final lines = File(path).readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (RegExp(r'(latitude|longitude|_lat|_lng)!?\.toStringAsFixed\((?:[2-9]|\d\d)\)').hasMatch(lines[i])) {
            offenders.add('$path:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('the settings and privacy texts say ~11 km (0.1°), not ~100 m', () {
      for (final path in [
        'lib/features/collector/presentation/screens/sensor_settings_screen.dart',
        'lib/core/localization/app_localizations.dart',
        'lib/features/collector/presentation/screens/imagery_upload_screen.dart',
      ]) {
        final text = File(path).readAsStringSync();
        expect(text.contains('~100m') || text.contains('~100 m'), isFalse, reason: path);
      }
      expect(
        File('lib/features/collector/presentation/screens/sensor_settings_screen.dart').readAsStringSync(),
        contains('~11 km (0.1°)'),
      );
    });
  });
}
