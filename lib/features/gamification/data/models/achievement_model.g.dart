// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'achievement_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AchievementModel _$AchievementModelFromJson(Map<String, dynamic> json) =>
    _AchievementModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      tier: json['tier'] as String,
      progress: (json['progress'] as num).toDouble(),
      earned: json['earned'] as bool,
      earnedAt: json['earnedAt'] as String?,
    );

Map<String, dynamic> _$AchievementModelToJson(_AchievementModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'tier': instance.tier,
      'progress': instance.progress,
      'earned': instance.earned,
      'earnedAt': instance.earnedAt,
    };
