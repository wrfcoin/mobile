import 'package:wrfcoin_mobile/features/weather/data/models/wrf_forecast_model.dart';

/// Test-only WRF forecast fixture: 24 synthetic hourly points marked
/// `isSimulated`. Moved out of lib/ by mobile#269 so the app can never render
/// device-generated forecast values; a source guard keeps it out.
WrfForecastModel wrfForecastSimulationStub(String location) {
  final base = DateTime.now().toUtc();

  List<WrfForecastPoint> hours = List.generate(24, (i) {
    final ts = base.add(Duration(hours: i));
    final tempC = 18.0 + (i % 12) * 0.5;
    return WrfForecastPoint(
      timestamp: ts.toIso8601String(),
      temperatureC: tempC,
      temperatureMaxC: tempC + 1.5,
      temperatureMinC: tempC - 1.5,
      precipitationMm: (i % 6 == 0) ? 0.2 : 0.0,
      windSpeedMs: 3.5 + (i % 8) * 0.3,
      forecastConfidence: 0.75,
      hdd: tempC < 18.3 ? 18.3 - tempC : 0.0,
      cdd: tempC > 18.3 ? tempC - 18.3 : 0.0,
    );
  });

  return WrfForecastModel(
    location: location,
    generatedAt: base.toIso8601String(),
    ipfsCid: 'Qm000000000000000000000000000000000000000000000',
    isSimulated: true,
    hourly: hours,
  );
}
