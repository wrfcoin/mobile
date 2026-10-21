/// The forecast detail (Hourly and 7-Day tabs), built from what the
/// backend's `GET /weather/forecast/:location` really returns (mobile#270).
///
/// Every value the payload does not carry is null and is shown as absent,
/// never as 0 or a sample value. Temperatures are °C, wind speeds km/h,
/// humidity %, and precipitation chance a 0–1 fraction.
library;

/// One NOAA hourly period (`?type=hourly`).
class HourlyForecast {
  const HourlyForecast({
    required this.timestamp,
    this.temperature,
    this.humidity,
    this.windSpeed,
    this.windDirection,
    this.precipitationProbability,
    this.shortForecast,
  });

  /// ISO-8601 start of the hour, with the forecast grid's UTC offset.
  final String timestamp;
  final double? temperature;
  final double? humidity;
  final double? windSpeed;
  final String? windDirection;
  final double? precipitationProbability;

  /// NOAA's short text, e.g. "Mostly Clear".
  final String? shortForecast;
}

/// One calendar day, merged from NOAA's day and night periods.
class DailyForecast {
  const DailyForecast({
    required this.date,
    this.tempMax,
    this.tempMin,
    this.humidityMin,
    this.humidityMax,
    this.windSpeed,
    this.precipitationProbability,
    this.shortForecast,
  });

  /// `YYYY-MM-DD`, the date at the forecast grid.
  final String date;

  /// The daytime period's temperature; null when the day has no daytime
  /// period left (e.g. only "Tonight").
  final double? tempMax;

  /// The night period's temperature; null when there is none.
  final double? tempMin;

  /// The day's relative-humidity range in whole percent (backend#1307);
  /// both null when NOAA's hourly data does not cover the day.
  final int? humidityMin;
  final int? humidityMax;

  /// The strongest wind among the day's periods.
  final double? windSpeed;
  final double? precipitationProbability;
  final String? shortForecast;
}

/// The detail for a location. A null list means that half of the forecast
/// is not available, as opposed to an error.
class ForecastDetail {
  const ForecastDetail({this.hourly, this.daily});

  final List<HourlyForecast>? hourly;
  final List<DailyForecast>? daily;
}
