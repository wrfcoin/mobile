import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final batteryMonitorProvider = Provider<BatteryMonitor>((ref) {
  return BatteryMonitor();
});

class BatteryMonitor {
  final Battery _battery = Battery();

  /// Whether battery monitoring is available on this platform.
  static bool get isAvailable => !kIsWeb;

  /// Returns the current battery level as a percentage (0-100).
  /// Returns -1 on web to indicate unavailability.
  Future<int> getBatteryLevel() async {
    if (kIsWeb) return -1;
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return 100; // Assume full battery if unavailable
    }
  }

  /// Returns true if collection should be paused to conserve battery.
  /// Always returns false on web (no battery monitoring).
  Future<bool> shouldPauseCollection({int threshold = 15}) async {
    if (kIsWeb) return false;
    final level = await getBatteryLevel();
    return level < threshold;
  }
}
