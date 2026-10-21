/// The latest observation from `GET /weather/current/:lat,lon` (backend
/// noaa-nws current-conditions read, mobile#332).
///
/// Every reading is nullable: the backend sends `null` for a value the
/// station did not report, and a real 0 stays 0. Nothing here defaults to
/// zero.
class CurrentConditions {
  final double? temperatureC;
  final double? relativeHumidityPercent;
  final double? barometricPressureHpa;
  final double? seaLevelPressureHpa;
  final double? windSpeedKmh;
  final String? observedAt;

  const CurrentConditions({
    this.temperatureC,
    this.relativeHumidityPercent,
    this.barometricPressureHpa,
    this.seaLevelPressureHpa,
    this.windSpeedKmh,
    this.observedAt,
  });

  /// Station pressure when reported, else sea-level pressure. Null only when
  /// neither is (a reported 0 is a value, not "missing").
  double? get pressureHpa => barometricPressureHpa ?? seaLevelPressureHpa;
}
