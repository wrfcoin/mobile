import 'package:freezed_annotation/freezed_annotation.dart';

part 'sensor_reading_model.freezed.dart';
part 'sensor_reading_model.g.dart';

@Freezed()
abstract class SensorReadingModel with _$SensorReadingModel {
  const factory SensorReadingModel({
    int? id,
    required double latitude,
    required double longitude,
    required double pressureHpa,
    required DateTime timestamp,
    @Default(false) bool synced,
  }) = _SensorReadingModel;

  factory SensorReadingModel.fromJson(Map<String, dynamic> json) =>
      _$SensorReadingModelFromJson(json);
}
