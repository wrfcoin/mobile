import '../../features/weather/domain/models/coarse_location.dart';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

class LocationService {
  /// The current permission, without asking. Never throws; an error reads
  /// as [LocationPermission.denied].
  Future<LocationPermission> checkPermission() async {
    try {
      return await Geolocator.checkPermission();
    } catch (e) {
      debugPrint('Location permission check failed: $e');
      return LocationPermission.denied;
    }
  }

  /// Opens this app's page in the system settings, where a permission that
  /// Android will no longer ask for can still be granted.
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('Could not open app settings: $e');
      return false;
    }
  }

  /// Opens the system location settings, where location can be turned on.
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('Could not open location settings: $e');
      return false;
    }
  }

  /// Shows the system permission dialog when Android can still show it.
  /// Returns whether location is now granted.
  Future<bool> requestPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      if (kIsWeb) {
        debugPrint('Location permission unavailable on web: $e');
      }
      return false;
    }
  }

  Future<Position?> getCurrentPosition() async {
    try {
      if (!await requestPermission()) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 50,
        ),
      );
    } catch (e) {
      debugPrint('Failed to get position: $e');
      return null;
    }
  }

  /// Rounds a coordinate to the 0.1 degree grid (~11 km) before it is stored, shown, logged or
  /// submitted (owner ruling 2026-09-30, the same grid as the Weather tab and the station cell).
  static double anonymize(double coordinate) =>
      CoarseLocation.coarsen(coordinate);
}
