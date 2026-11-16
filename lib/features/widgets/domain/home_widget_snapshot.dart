import '../../collector/data/models/sensor_reading_model.dart';
import '../../weather/data/models/forecast_model.dart';

class HomeWidgetSnapshot {
  const HomeWidgetSnapshot({
    this.weatherLocation,
    this.weatherTimestamp,
    this.weatherTemperature,
    this.weatherPressure,
    this.weatherHumidity,
    this.weatherWindSpeed,
    this.pressureHpa,
    this.readingCapturedAt,
    required this.pendingSyncCount,
    this.lastSubmissionStatus,
  });

  final String? weatherLocation;
  final String? weatherTimestamp;
  final double? weatherTemperature;
  final double? weatherPressure;
  final double? weatherHumidity;
  final double? weatherWindSpeed;
  final double? pressureHpa;
  final DateTime? readingCapturedAt;
  final int pendingSyncCount;
  final String? lastSubmissionStatus;

  Map<String, dynamic> toJson() {
    return {
      if (weatherLocation != null) 'weatherLocation': weatherLocation,
      if (weatherTimestamp != null) 'weatherTimestamp': weatherTimestamp,
      if (weatherTemperature != null) 'weatherTemperature': weatherTemperature,
      if (weatherPressure != null) 'weatherPressure': weatherPressure,
      if (weatherHumidity != null) 'weatherHumidity': weatherHumidity,
      if (weatherWindSpeed != null) 'weatherWindSpeed': weatherWindSpeed,
      if (pressureHpa != null) 'pressureHpa': pressureHpa,
      if (readingCapturedAt != null)
        'capturedAt': readingCapturedAt!.toUtc().toIso8601String(),
      'pendingSyncCount': pendingSyncCount,
      'lastSubmissionStatus': lastSubmissionStatus,
    };
  }

  static HomeWidgetSnapshot? tryParse(Map<String, dynamic> value) {
    return HomeWidgetSnapshot(
      weatherLocation: _asString(value['weatherLocation']),
      weatherTimestamp: _asString(value['weatherTimestamp']),
      weatherTemperature: _asDouble(value['weatherTemperature']),
      weatherPressure: _asDouble(value['weatherPressure']),
      weatherHumidity: _asDouble(value['weatherHumidity']),
      weatherWindSpeed: _asDouble(value['weatherWindSpeed']),
      pressureHpa: _asDouble(value['pressureHpa']),
      readingCapturedAt: _asDateTime(value['capturedAt']),
      pendingSyncCount: _asInt(value['pendingSyncCount']) ?? 0,
      lastSubmissionStatus: _asString(value['lastSubmissionStatus']),
    );
  }

  static HomeWidgetSnapshot fromParts({
    required int pendingSyncCount,
    required String? lastSubmissionStatus,
    SensorReadingModel? reading,
    ForecastModel? weather,
  }) {
    return HomeWidgetSnapshot(
      pendingSyncCount: pendingSyncCount,
      lastSubmissionStatus: lastSubmissionStatus,
      pressureHpa: reading?.pressureHpa,
      readingCapturedAt: reading?.timestamp,
      weatherLocation: weather?.location,
      weatherTimestamp: weather?.timestamp,
      weatherTemperature: weather?.temperature,
      weatherPressure: weather?.pressure,
      weatherHumidity: weather?.humidity,
      weatherWindSpeed: weather?.windSpeed,
    );
  }
}

String? _asString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? _asDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  if (value is int) {
    return DateTime.tryParse(value.toString());
  }
  return null;
}
