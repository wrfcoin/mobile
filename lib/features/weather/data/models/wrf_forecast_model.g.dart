// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wrf_forecast_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WrfForecastPoint _$WrfForecastPointFromJson(Map<String, dynamic> json) =>
    _WrfForecastPoint(
      timestamp: json['timestamp'] as String,
      temperatureC: (json['temperatureC'] as num).toDouble(),
      temperatureMaxC: (json['temperatureMaxC'] as num).toDouble(),
      temperatureMinC: (json['temperatureMinC'] as num).toDouble(),
      precipitationMm: (json['precipitationMm'] as num).toDouble(),
      windSpeedMs: (json['windSpeedMs'] as num).toDouble(),
      forecastConfidence:
          (json['forecastConfidence'] as num?)?.toDouble() ?? 1.0,
      hdd: (json['hdd'] as num?)?.toDouble() ?? 0.0,
      cdd: (json['cdd'] as num?)?.toDouble() ?? 0.0,
    );

Map<String, dynamic> _$WrfForecastPointToJson(_WrfForecastPoint instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp,
      'temperatureC': instance.temperatureC,
      'temperatureMaxC': instance.temperatureMaxC,
      'temperatureMinC': instance.temperatureMinC,
      'precipitationMm': instance.precipitationMm,
      'windSpeedMs': instance.windSpeedMs,
      'forecastConfidence': instance.forecastConfidence,
      'hdd': instance.hdd,
      'cdd': instance.cdd,
    };

_WrfForecastModel _$WrfForecastModelFromJson(Map<String, dynamic> json) =>
    _WrfForecastModel(
      location: json['location'] as String,
      generatedAt: json['generatedAt'] as String,
      ipfsCid: json['ipfsCid'] as String,
      isSimulated: json['isSimulated'] as bool? ?? false,
      hourly:
          (json['hourly'] as List<dynamic>?)
              ?.map((e) => WrfForecastPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$WrfForecastModelToJson(_WrfForecastModel instance) =>
    <String, dynamic>{
      'location': instance.location,
      'generatedAt': instance.generatedAt,
      'ipfsCid': instance.ipfsCid,
      'isSimulated': instance.isSimulated,
      'hourly': instance.hourly,
    };
