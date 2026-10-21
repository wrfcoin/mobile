import 'package:flutter/material.dart';

import 'weather_narrative.dart';

/// Air-temperature history for the phone's 0.1 degree cell, from station
/// submissions (backend `GET /api/weather/temperature-history`, owner ruling
/// 2026-09-30 "Station data now"). Every value is nullable: a missing or
/// malformed field is unknown, never a number.
double? _asDouble(Object? v) {
  if (v is num && v.isFinite) return v.toDouble();
  return null;
}

final RegExp _dateShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A UTC calendar date (midnight UTC) from `YYYY-MM-DD`, or null.
DateTime? _parseDay(Object? v) {
  if (v is! String || !_dateShape.hasMatch(v)) return null;
  final d = DateTime.tryParse('${v}T00:00:00Z');
  if (d == null || d.toIso8601String().substring(0, 10) != v) return null;
  return d;
}

class DailyStationTemperature {
  const DailyStationTemperature({
    required this.day,
    this.minC,
    this.maxC,
    this.meanC,
  });

  /// UTC calendar day.
  final DateTime day;
  final double? minC;
  final double? maxC;
  final double? meanC;

  bool get hasValues => minC != null || maxC != null || meanC != null;
}

class StationTemperatureHistory {
  const StationTemperatureHistory({required this.daily});

  /// Days the backend reported. A day with null aggregates is "no data".
  /// Sample counts are deliberately not read: the backend may omit them
  /// (or give only a coarse bucket), and no narrative depends on them.
  final List<DailyStationTemperature> daily;

  bool get hasData => daily.any((d) => d.hasValues);

  factory StationTemperatureHistory.fromJson(Map<String, dynamic> json) {
    final rows = json['daily'];
    final daily = <DailyStationTemperature>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final day = _parseDay(row['date']);
        if (day == null) continue;
        daily.add(
          DailyStationTemperature(
            day: day,
            minC: _asDouble(row['minC']),
            maxC: _asDouble(row['maxC']),
            meanC: _asDouble(row['meanC']),
          ),
        );
      }
    }
    daily.sort((a, b) => a.day.compareTo(b.day));
    return StationTemperatureHistory(daily: daily);
  }
}

const String kStationNarrativeSource = 'station:temperature-history';

String _ymd(DateTime d) => d.toIso8601String().substring(0, 10);

String _deg(double v) => '${v.toStringAsFixed(1)}°C';

/// Narratives from [history]; nothing is invented: a day with no data breaks
/// every run and is never bridged, and with no data the list is empty.
///
/// Only COMPLETED UTC days count (the backend reports completed days only):
/// today and any future row are ignored here, so a partial day can never
/// drive a comparison, a range, a run or a provenance window. "Yesterday" is
/// the UTC day before the UTC date of [now].
List<WeatherNarrative> buildStationTemperatureNarratives(
  StationTemperatureHistory history,
  DateTime now,
) {
  final utcNow = now.toUtc();
  final today = DateTime.utc(utcNow.year, utcNow.month, utcNow.day);
  DateTime before(DateTime d, int n) => d.subtract(Duration(days: n));
  final days = [
    for (final d in history.daily)
      if (d.day.isBefore(today) && d.hasValues) d,
  ];
  if (days.isEmpty) return const [];
  final byDay = {for (final d in days) d.day: d};

  final provenance = WeatherNarrativeProvenance(
    source: kStationNarrativeSource,
    observationCount: days.length,
    observedFrom: days.first.day,
    observedTo: days.last.day,
  );
  final out = <WeatherNarrative>[];
  final yesterday = before(today, 1);

  // Yesterday against the day before it (both completed, adjacent days).
  final yesterdayMean = byDay[yesterday]?.meanC;
  final twoAgoMean = byDay[before(today, 2)]?.meanC;
  if (yesterdayMean != null && twoAgoMean != null) {
    final diff = yesterdayMean - twoAgoMean;
    final same = diff.abs() < 0.05;
    out.add(
      WeatherNarrative(
        type: NarrativeType.digest,
        title: same
            ? 'Yesterday was about the same as the day before'
            : 'Yesterday was ${diff > 0 ? 'warmer' : 'cooler'} than the day before by ${diff.abs().toStringAsFixed(1)}°C',
        description: 'Average air temperature at nearby stations, yesterday compared with the day before.',
        date: yesterday,
        value: diff,
        icon: diff >= 0.05 ? Icons.trending_up : Icons.trending_down,
        provenance: provenance,
      ),
    );
  }

  // Range over the 7 completed UTC days ending yesterday.
  double? lo;
  double? hi;
  var rangeDays = 0;
  for (var i = 1; i <= 7; i++) {
    final d = byDay[before(today, i)];
    if (d == null || d.minC == null || d.maxC == null) continue;
    rangeDays++;
    lo = lo == null || d.minC! < lo ? d.minC : lo;
    hi = hi == null || d.maxC! > hi ? d.maxC : hi;
  }
  if (lo != null && hi != null) {
    out.add(
      WeatherNarrative(
        type: NarrativeType.digest,
        title: 'Past 7 days: ${_deg(lo)} to ${_deg(hi)}',
        description:
            'Lowest and highest air temperature reported by nearby stations over $rangeDays '
            '${rangeDays == 1 ? 'day' : 'days'} with data.',
        date: yesterday,
        value: hi - lo,
        icon: Icons.thermostat,
        provenance: provenance,
      ),
    );
  }

  // Runs of 3 consecutive calendar days; a day with no data breaks the run.
  int heat = 0;
  int cold = 0;
  DateTime? previous;
  for (final d in days) {
    final consecutive =
        previous != null && d.day.difference(previous).inDays == 1;
    if (!consecutive) {
      heat = 0;
      cold = 0;
    }
    previous = d.day;
    if (d.maxC != null && d.maxC! >= 35) {
      heat++;
      if (heat == 3) {
        out.add(
          WeatherNarrative(
            type: NarrativeType.event,
            title: 'Heat wave nearby',
            description: 'Nearby stations reported 3+ consecutive days at or above 35°C. Stay hydrated and check on neighbors.',
            date: d.day,
            icon: Icons.whatshot,
            provenance: provenance,
          ),
        );
      }
    } else {
      heat = 0;
    }
    if (d.minC != null && d.minC! <= -5) {
      cold++;
      if (cold == 3) {
        out.add(
          WeatherNarrative(
            type: NarrativeType.event,
            title: 'Cold snap nearby',
            description: 'Nearby stations reported 3+ consecutive days at or below -5°C. Protect pipes and pets.',
            date: d.day,
            icon: Icons.severe_cold,
            provenance: provenance,
          ),
        );
      }
    } else {
      cold = 0;
    }
  }

  // Frost: the most recent day with a minimum at or below 0°C.
  for (final d in days.reversed) {
    if (d.minC != null && d.minC! <= 0) {
      out.add(
        WeatherNarrative(
          type: NarrativeType.event,
          title: 'Frost nearby',
          description:
              'Nearby stations reached ${_deg(d.minC!)} on ${_ymd(d.day)}.',
          date: d.day,
          value: d.minC,
          icon: Icons.ac_unit,
          provenance: provenance,
        ),
      );
      break;
    }
  }

  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}
