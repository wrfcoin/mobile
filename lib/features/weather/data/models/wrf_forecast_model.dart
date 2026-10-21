import 'package:freezed_annotation/freezed_annotation.dart';

part 'wrf_forecast_model.freezed.dart';
part 'wrf_forecast_model.g.dart';

/// A single WRF model forecast slot (hourly resolution).
@Freezed()
abstract class WrfForecastPoint with _$WrfForecastPoint {
  const factory WrfForecastPoint({
    /// ISO-8601 timestamp for this forecast slot.
    required String timestamp,

    /// Mean air temperature in degrees Celsius.
    required double temperatureC,

    /// Maximum temperature for this slot (°C).
    required double temperatureMaxC,

    /// Minimum temperature for this slot (°C).
    required double temperatureMinC,

    /// Total precipitation in millimetres.
    required double precipitationMm,

    /// Wind speed in metres per second.
    required double windSpeedMs,

    /// Model confidence score between 0.0 (low) and 1.0 (high).
    @Default(1.0) double forecastConfidence,

    /// Heating degree days relative to base temperature 18.3°C.
    @Default(0.0) double hdd,

    /// Cooling degree days relative to base temperature 18.3°C.
    @Default(0.0) double cdd,
  }) = _WrfForecastPoint;

  factory WrfForecastPoint.fromJson(Map<String, dynamic> json) =>
      _$WrfForecastPointFromJson(json);
}

/// Full WRF model output for a location — returned by
/// `GET /api/v1/weather/wrf-forecast/<location>`.
@Freezed()
abstract class WrfForecastModel with _$WrfForecastModel {
  const factory WrfForecastModel({
    /// Location identifier.
    required String location,

    /// ISO-8601 timestamp when the WRF model run was generated.
    required String generatedAt,

    /// IPFS content identifier of the WRF NetCDF/output file.
    required String ipfsCid,

    /// `false` when this contains real WRF model output; `true` when the
    /// server itself labels its payload a simulation.
    @Default(false) bool isSimulated,

    /// Hourly forecast points for the next 48 hours (or whatever the model
    /// run covers).
    @Default([]) List<WrfForecastPoint> hourly,
  }) = _WrfForecastModel;

  factory WrfForecastModel.fromJson(Map<String, dynamic> json) =>
      _$WrfForecastModelFromJson(json);
}
