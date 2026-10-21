import 'package:freezed_annotation/freezed_annotation.dart';

part 'achievement_model.freezed.dart';
part 'achievement_model.g.dart';

@Freezed()
sealed class AchievementModel with _$AchievementModel {
  const factory AchievementModel({
    required String id,
    required String name,
    required String description,
    required String tier,
    required double progress,
    required bool earned,
    String? earnedAt,
  }) = _AchievementModel;

  factory AchievementModel.fromJson(Map<String, dynamic> json) =>
      _$AchievementModelFromJson(json);
}
