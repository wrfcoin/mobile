import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../../services/location/location_service.dart';

final sensorDataSourceProvider = Provider<SensorDataSource>((ref) {
  return SensorDataSource(ref.watch(locationServiceProvider));
});

class SensorDataSource {
  final LocationService _locationService;

  SensorDataSource(this._locationService);

  /// Whether this phone has a barometer: true once it gives a reading, false
  /// only when the platform says there is no such sensor, null when it could
  /// not tell (no sensor plugin, as on the web). No timer: a barometer answers
  /// at once, and a missing one is an immediate error.
  Future<bool?> hasBarometer() async {
    try {
      await barometerEventStream().first;
      return true;
    } on PlatformException catch (error) {
      return error.code == 'NO_SENSOR' ? false : null;
    } catch (_) {
      return null;
    }
  }

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
    final position = await _locationService.getRoughPosition();
    if (position == null) return null;

    return (
      lat: LocationService.anonymize(position.latitude),
      lng: LocationService.anonymize(position.longitude),
    );
  }

  /// [readLocation] for the collection service: no permission dialog.
  Future<({double lat, double lng})?> readLocationQuietly() async {
    final position = await _locationService.getQuietPosition();
    if (position == null) return null;

    return (
      lat: LocationService.anonymize(position.latitude),
      lng: LocationService.anonymize(position.longitude),
    );
  }
}
