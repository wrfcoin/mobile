// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sensor_reading_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SensorReadingModel _$SensorReadingModelFromJson(Map<String, dynamic> json) =>
    _SensorReadingModel(
      id: (json['id'] as num?)?.toInt(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      pressureHpa: (json['pressureHpa'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      synced: json['synced'] as bool? ?? false,
    );

Map<String, dynamic> _$SensorReadingModelToJson(_SensorReadingModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'pressureHpa': instance.pressureHpa,
      'timestamp': instance.timestamp.toIso8601String(),
      'synced': instance.synced,
    };
