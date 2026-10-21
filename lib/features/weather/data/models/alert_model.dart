import 'package:freezed_annotation/freezed_annotation.dart';

part 'alert_model.freezed.dart';
part 'alert_model.g.dart';

@Freezed()
sealed class AlertModel with _$AlertModel {
  const factory AlertModel({
    required String id,
    required String type,
    required String severity,
    required String location,
    required String timestamp,
    required String description,
  }) = _AlertModel;

  factory AlertModel.fromJson(Map<String, dynamic> json) =>
      _$AlertModelFromJson(json);
}
