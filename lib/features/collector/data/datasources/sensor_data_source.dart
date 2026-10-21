import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../../services/location/location_service.dart';

final sensorDataSourceProvider = Provider<SensorDataSource>((ref) {
  return SensorDataSource(ref.watch(locationServiceProvider));
});

class SensorDataSource {
  final LocationService _locationService;

  SensorDataSource(this._locationService);

  /// Reads barometric pressure from the device barometer sensor.
  /// Returns pressure in hPa, or null if unavailable.
  Future<double?> readBarometer() async {
    try {
      final event = await barometerEventStream().first.timeout(
        const Duration(seconds: 5),
      );
      return event.pressure;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Reads the current GPS location with privacy anonymization
  /// (rounded to the 0.1 degree grid, ~11 km).
  Future<({double lat, double lng})?> readLocation() async {
    final position = await _locationService.getCurrentPosition();
    if (position == null) return null;

    return (
      lat: LocationService.anonymize(position.latitude),
      lng: LocationService.anonymize(position.longitude),
    );
  }
}
