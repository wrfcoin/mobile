// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'forecast_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ForecastModel _$ForecastModelFromJson(Map<String, dynamic> json) =>
    _ForecastModel(
      temperature: (json['temperature'] as num?)?.toDouble(),
      humidity: (json['humidity'] as num?)?.toDouble(),
      pressure: (json['pressure'] as num?)?.toDouble(),
      windSpeed: (json['windSpeed'] as num?)?.toDouble(),
      windDirection: json['windDirection'] as String?,
      precipitation: (json['precipitation'] as num?)?.toDouble(),
      aqi: (json['aqi'] as num?)?.toInt(),
      wildfireRisk: (json['wildfireRisk'] as num?)?.toDouble(),
      location: json['location'] as String,
      timestamp: json['timestamp'] as String,
    );

Map<String, dynamic> _$ForecastModelToJson(_ForecastModel instance) =>
    <String, dynamic>{
      'temperature': instance.temperature,
      'humidity': instance.humidity,
      'pressure': instance.pressure,
      'windSpeed': instance.windSpeed,
      'windDirection': instance.windDirection,
      'precipitation': instance.precipitation,
      'aqi': instance.aqi,
      'wildfireRisk': instance.wildfireRisk,
      'location': instance.location,
      'timestamp': instance.timestamp,
    };
