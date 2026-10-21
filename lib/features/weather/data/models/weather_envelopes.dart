import 'alert_model.dart';
import 'current_conditions_model.dart';
import 'forecast_detail_model.dart';
import 'forecast_model.dart';

/// Parsers for the backend's weather envelopes (backend
/// `server/controllers/enhanced-weather-controller.js`, NOAA-NWS source).
///
/// Only values the payload really contains are mapped; anything absent stays
/// null and renders as '—'. Nothing is defaulted to zero.

/// Label for a forecast keyed by the device's rounded location.
const forecastAreaLabel = 'Your area';

/// Maps `GET /weather/forecast/:lat,lon`:
/// `{ location, forecast: { periods: [...] }, source, timestamp }`.
///
/// Returns null when the payload is not that envelope or has no periods.
ForecastModel? forecastFromEnvelope(Object? payload) {
  if (payload is! Map) return null;
  final forecast = payload['forecast'];
  if (forecast is! Map) return null;
  final periods = forecast['periods'];
  if (periods is! List || periods.isEmpty) return null;
  final period = periods.first;
  if (period is! Map) return null;

  final timestamp = period['startTime'] ?? payload['timestamp'];
  return ForecastModel(
    temperature: _celsius(period['temperature'], period['temperatureUnit']),
    humidity: _hourlyPercent(period['relativeHumidity']),
    windSpeed: _windKmh(period['windSpeed']),
    windDirection: period['windDirection'] is String
        ? period['windDirection'] as String
        : null,
    location: forecastAreaLabel,
    timestamp: timestamp is String ? timestamp : '',
  );
}

/// Maps `GET /weather/current/:lat,lon`:
/// `{ location, current: { temperatureC, relativeHumidityPercent,
/// barometricPressureHpa, seaLevelPressureHpa, windSpeedKmh, observedAt },
/// source, timestamp }`.
///
/// Returns null when the payload is not that envelope. A missing or
/// non-numeric reading is null, never 0.
CurrentConditions? currentFromEnvelope(Object? payload) {
  if (payload is! Map) return null;
  final current = payload['current'];
  if (current is! Map) return null;
  double? number(String key) {
    final value = current[key];
    return value is num ? value.toDouble() : null;
  }

  return CurrentConditions(
    temperatureC: number('temperatureC'),
    relativeHumidityPercent: number('relativeHumidityPercent'),
    barometricPressureHpa: number('barometricPressureHpa'),
    seaLevelPressureHpa: number('seaLevelPressureHpa'),
    windSpeedKmh: number('windSpeedKmh'),
    observedAt: _string(current['observedAt']),
  );
}

/// The periods of a forecast envelope, or null when [payload] is not one or
/// has none.
List<Map>? _periods(Object? payload) {
  if (payload is! Map) return null;
  final forecast = payload['forecast'];
  if (forecast is! Map) return null;
  final periods = forecast['periods'];
  if (periods is! List) return null;
  final maps = periods.whereType<Map>().toList();
  return maps.isEmpty ? null : maps;
}

/// Maps `GET /weather/forecast/:lat,lon?type=hourly` (backend
/// noaa-nws-api-service getHourlyForecast): NOAA hourly periods with
/// `relativeHumidity` and `probabilityOfPrecipitation` quantities.
///
/// Returns null when there are no hourly periods.
List<HourlyForecast>? hourlyFromEnvelope(Object? payload) {
  final periods = _periods(payload);
  if (periods == null) return null;
  final hours = [
    for (final period in periods)
      if (_string(period['startTime']) case final start?)
        HourlyForecast(
          timestamp: start,
          temperature: _celsius(
            period['temperature'],
            period['temperatureUnit'],
          ),
          humidity: _hourlyPercent(period['relativeHumidity']),
          windSpeed: _windKmh(period['windSpeed']),
          windDirection: _string(period['windDirection']),
          precipitationProbability: _fraction(
            period['probabilityOfPrecipitation'],
          ),
          shortForecast: _string(period['shortForecast']),
        ),
  ];
  return hours.isEmpty ? null : hours;
}

/// Maps `GET /weather/forecast/:lat,lon` (backend noaa-nws-api-service
/// getForecast): NOAA's 12-hour day and night periods, merged into calendar
/// days at the forecast grid. The daytime period gives the high, the night
/// period the low. At most [maxDays] days.
///
/// Returns null when there are no periods.
List<DailyForecast>? dailyFromEnvelope(Object? payload, {int maxDays = 7}) {
  final periods = _periods(payload);
  if (periods == null) return null;
  final byDate = <String, List<Map>>{};
  for (final period in periods) {
    final start = _string(period['startTime']);
    // The offset is the grid's, so the first 10 characters are its date.
    if (start == null || start.length < 10) continue;
    byDate.putIfAbsent(start.substring(0, 10), () => []).add(period);
  }
  final days = <DailyForecast>[];
  for (final MapEntry(key: date, value: dayPeriods) in byDate.entries) {
    if (days.length == maxDays) break;
    Map? daytime;
    Map? night;
    for (final period in dayPeriods) {
      if (period['isDaytime'] == true) {
        daytime ??= period;
      } else if (period['isDaytime'] == false) {
        night ??= period;
      }
    }
    final winds = [
      for (final period in dayPeriods) ?_windKmh(period['windSpeed']),
    ];
    final ranges = [
      for (final period in dayPeriods)
        ?_humidityRange(period['relativeHumidity']),
    ];
    final chances = [
      for (final period in dayPeriods)
        ?_fraction(period['probabilityOfPrecipitation']),
    ];
    days.add(
      DailyForecast(
        date: date,
        tempMax: daytime == null
            ? null
            : _celsius(daytime['temperature'], daytime['temperatureUnit']),
        tempMin: night == null
            ? null
            : _celsius(night['temperature'], night['temperatureUnit']),
        humidityMin: ranges.isEmpty
            ? null
            : ranges.map((r) => r.min).reduce((a, b) => a < b ? a : b),
        humidityMax: ranges.isEmpty
            ? null
            : ranges.map((r) => r.max).reduce((a, b) => a > b ? a : b),
        windSpeed: winds.isEmpty ? null : winds.reduce((a, b) => a > b ? a : b),
        precipitationProbability: chances.isEmpty
            ? null
            : chances.reduce((a, b) => a > b ? a : b),
        shortForecast: _string((daytime ?? night)?['shortForecast']),
      ),
    );
  }
  return days.isEmpty ? null : days;
}

/// Maps `GET /weather/alerts/:lat,lon`: `{ alerts: [...], count, source }`.
///
/// Returns null when the payload is not that envelope. Alerts without an id
/// or event name are dropped rather than shown with invented text.
List<AlertModel>? alertsFromEnvelope(Object? payload) {
  if (payload is! Map) return null;
  final alerts = payload['alerts'];
  if (alerts is! List) return null;
  return [
    for (final alert in alerts)
      if (alert is Map && alert['id'] is String && alert['event'] is String)
        AlertModel(
          id: alert['id'] as String,
          type: alert['event'] as String,
          severity: _string(alert['severity']) ?? 'unknown',
          location: _string(alert['areaDesc']) ?? '',
          timestamp:
              _string(alert['effective']) ??
              _string(alert['onset']) ??
              _string(alert['sent']) ??
              '',
          description:
              _string(alert['headline']) ?? _string(alert['description']) ?? '',
        ),
  ];
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

double? _celsius(Object? value, Object? unit) {
  if (value is! num) return null;
  return switch (unit) {
    'F' => (value - 32) * 5 / 9,
    'C' => value.toDouble(),
    _ => null,
  };
}

/// NOAA hourly periods carry `{ unitCode, value }` quantities.
double? _quantityValue(Object? quantity) {
  if (quantity is! Map) return null;
  final value = quantity['value'];
  return value is num ? value.toDouble() : null;
}

/// An hourly `relativeHumidity`: a plain percent (backend#1307), or the old
/// NOAA `{unitCode, value}` object the not-yet-redeployed backend still sends.
/// Anything else is absent, never 0.
double? _hourlyPercent(Object? value) =>
    value is num ? value.toDouble() : _quantityValue(value);

/// A daily `relativeHumidity` `{min, max}` in percent, or null.
({int min, int max})? _humidityRange(Object? value) {
  if (value is! Map) return null;
  final min = value['min'];
  final max = value['max'];
  if (min is! num || max is! num) return null;
  return (min: min.round(), max: max.round());
}

/// A NOAA percent quantity as a 0–1 fraction.
double? _fraction(Object? quantity) {
  final percent = _quantityValue(quantity);
  return percent == null ? null : percent / 100;
}

/// NOAA reports wind as text such as "10 mph" or "5 to 10 mph"; a range maps
/// to its upper bound.
double? _windKmh(Object? text) {
  if (text is! String) return null;
  final numbers = RegExp(r'\d+(?:\.\d+)?')
      .allMatches(text)
      .map((m) => double.parse(m.group(0)!))
      .toList();
  if (numbers.isEmpty) return null;
  final top = numbers.reduce((a, b) => a > b ? a : b);
  final lower = text.toLowerCase();
  if (lower.contains('mph')) return top * 1.609344;
  if (lower.contains('km/h')) return top;
  return null;
}
