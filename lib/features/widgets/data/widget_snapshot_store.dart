import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../collector/data/models/sensor_reading_model.dart';
import '../../weather/data/models/forecast_model.dart';
import '../domain/home_widget_snapshot.dart';

/// Platform-neutral cache consumed by future Android/iOS widget extensions.
///
/// It intentionally contains collection evidence and weather context, not an
/// invented earning-rate claim. The snapshot is a seam for runtime extensions.
class WidgetSnapshotStore {
  static const _key = 'home_widget_snapshot_v1';

  Future<void> write({
    required SensorReadingModel reading,
    required int pendingSyncCount,
    required String? lastSubmissionStatus,
    required bool rewardTotalsAvailable,
    required double earnedRewardWrf,
  }) async {
    await writeCollectionSlice(
      reading: reading,
      pendingSyncCount: pendingSyncCount,
      lastSubmissionStatus: lastSubmissionStatus,
      rewardTotalsAvailable: rewardTotalsAvailable,
      earnedRewardWrf: earnedRewardWrf,
    );
  }

  Future<void> writeCollectionSlice({
    SensorReadingModel? reading,
    required int pendingSyncCount,
    required String? lastSubmissionStatus,
    required bool rewardTotalsAvailable,
    required double earnedRewardWrf,
  }) async {
    final Map<String, dynamic> patch = {
      'pendingSyncCount': pendingSyncCount,
      'lastSubmissionStatus': lastSubmissionStatus,
      'rewardTotalsAvailable': rewardTotalsAvailable,
      if (rewardTotalsAvailable) 'earnedRewardWrf': earnedRewardWrf,
    };
    if (reading != null) {
      patch['pressureHpa'] = reading.pressureHpa;
      patch['capturedAt'] = reading.timestamp.toUtc().toIso8601String();
    }

    await _writePatch(patch);
  }

  Future<void> writeWeatherSlice(ForecastModel? forecast) async {
    if (forecast == null) return;
    await _writePatch({
      'weatherLocation': forecast.location,
      'weatherTimestamp': forecast.timestamp,
      'weatherTemperature': forecast.temperature,
      'weatherPressure': forecast.pressure,
      'weatherHumidity': forecast.humidity,
      'weatherWindSpeed': forecast.windSpeed,
    });
  }

  Future<HomeWidgetSnapshot?> readSnapshot() async {
    final map = await read();
    if (map == null) return null;
    return HomeWidgetSnapshot.tryParse(map);
  }

  Future<void> writeSnapshot(HomeWidgetSnapshot snapshot) async {
    await _write(snapshot.toJson());
  }

  Future<Map<String, dynamic>?> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<void> _writePatch(Map<String, dynamic> patch) async {
    final current = await read() ?? {};
    current.addAll(patch);
    await _write(current);
  }

  Future<void> _write(Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value));
  }
}
