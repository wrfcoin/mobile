// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alert_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AlertModel _$AlertModelFromJson(Map<String, dynamic> json) => _AlertModel(
  id: json['id'] as String,
  type: json['type'] as String,
  severity: json['severity'] as String,
  location: json['location'] as String,
  timestamp: json['timestamp'] as String,
  description: json['description'] as String,
);

Map<String, dynamic> _$AlertModelToJson(_AlertModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'severity': instance.severity,
      'location': instance.location,
      'timestamp': instance.timestamp,
      'description': instance.description,
    };
