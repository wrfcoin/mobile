import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlertSettings {
  final double aqiThreshold;
  final double tempMin;
  final double tempMax;
  final bool severeWeather;
  final bool airQuality;
  final bool wildfire;

  const AlertSettings({
    this.aqiThreshold = 100,
    this.tempMin = 0,
    this.tempMax = 40,
    this.severeWeather = true,
    this.airQuality = true,
    this.wildfire = true,
  });

  AlertSettings copyWith({
    double? aqiThreshold,
    double? tempMin,
    double? tempMax,
    bool? severeWeather,
    bool? airQuality,
    bool? wildfire,
  }) {
    return AlertSettings(
      aqiThreshold: aqiThreshold ?? this.aqiThreshold,
      tempMin: tempMin ?? this.tempMin,
      tempMax: tempMax ?? this.tempMax,
      severeWeather: severeWeather ?? this.severeWeather,
      airQuality: airQuality ?? this.airQuality,
      wildfire: wildfire ?? this.wildfire,
    );
  }
}

final alertSettingsProvider =
    AsyncNotifierProvider<AlertSettingsNotifier, AlertSettings>(
      AlertSettingsNotifier.new,
    );

class AlertSettingsNotifier extends AsyncNotifier<AlertSettings> {
  static const _aqiThresholdKey = 'alert_settings.aqi_threshold';
  static const _tempMinKey = 'alert_settings.temp_min';
  static const _tempMaxKey = 'alert_settings.temp_max';
  static const _severeWeatherKey = 'alert_settings.severe_weather';
  static const _airQualityKey = 'alert_settings.air_quality';
  static const _wildfireKey = 'alert_settings.wildfire';

  @override
  Future<AlertSettings> build() async {
    return _read();
  }

  Future<AlertSettings> _read() async {
    final prefs = await SharedPreferences.getInstance();
    return AlertSettings(
      aqiThreshold: prefs.getDouble(_aqiThresholdKey) ?? 100,
      tempMin: prefs.getDouble(_tempMinKey) ?? 0,
      tempMax: prefs.getDouble(_tempMaxKey) ?? 40,
      severeWeather: prefs.getBool(_severeWeatherKey) ?? true,
      airQuality: prefs.getBool(_airQualityKey) ?? true,
      wildfire: prefs.getBool(_wildfireKey) ?? true,
    );
  }

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_read);
  }

  Future<void> save(AlertSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setDouble(_aqiThresholdKey, settings.aqiThreshold),
      prefs.setDouble(_tempMinKey, settings.tempMin),
      prefs.setDouble(_tempMaxKey, settings.tempMax),
      prefs.setBool(_severeWeatherKey, settings.severeWeather),
      prefs.setBool(_airQualityKey, settings.airQuality),
      prefs.setBool(_wildfireKey, settings.wildfire),
    ]);
    state = AsyncData(settings);
  }
}
