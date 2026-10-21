import 'package:freezed_annotation/freezed_annotation.dart';

part 'forecast_model.freezed.dart';
part 'forecast_model.g.dart';

@Freezed()
sealed class ForecastModel with _$ForecastModel {
  const factory ForecastModel({
    double? temperature,
    double? humidity,
    double? pressure,
    double? windSpeed,
    String? windDirection,
    double? precipitation,
    int? aqi,
    double? wildfireRisk,
    required String location,
    required String timestamp,
  }) = _ForecastModel;

  factory ForecastModel.fromJson(Map<String, dynamic> json) =>
      _$ForecastModelFromJson(json);
}
