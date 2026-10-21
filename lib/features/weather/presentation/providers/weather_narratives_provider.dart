import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../collector/data/repositories/collector_repository_impl.dart';
import '../../domain/models/weather_narrative.dart';

/// A single sensor data point used for narrative analysis.
class SensorSnapshot {
  final int? readingId;
  final DateTime timestamp;
  final double? temperatureC;
  final int? humidityPercent;
  final double pressureHpa;

  const SensorSnapshot({
    this.readingId,
    required this.timestamp,
    this.temperatureC,
    this.humidityPercent,
    required this.pressureHpa,
  });
}

abstract class WeatherHistoryRepository {
  Future<List<SensorSnapshot>> loadHistory();
}

class PersistedWeatherHistoryRepository implements WeatherHistoryRepository {
  final CollectorRepository _collectorRepository;

  const PersistedWeatherHistoryRepository(this._collectorRepository);

  @override
  Future<List<SensorSnapshot>> loadHistory() async {
    final readings = await _collectorRepository.getReadingHistory();
    return readings
        .map(
          (reading) => SensorSnapshot(
            readingId: reading.id,
            timestamp: reading.timestamp,
            pressureHpa: reading.pressureHpa,
          ),
        )
        .toList(growable: false);
  }
}

final weatherHistoryRepositoryProvider = Provider<WeatherHistoryRepository>((
  ref,
) {
  return PersistedWeatherHistoryRepository(
    ref.watch(collectorRepositoryProvider),
  );
});

class WeatherNarrativesState {
  final List<WeatherNarrative> narratives;
  final bool isLoading;
  final String? error;

  const WeatherNarrativesState({
    this.narratives = const [],
    this.isLoading = false,
    this.error,
  });
}

/// Analyzes sensor reading history and produces weather narratives.
///
/// Detection logic:
/// - **Personal records**: all-time highs/lows for temp, humidity, pressure
/// - **Streaks**: consecutive days with readings
/// - **Events**: rapid pressure drop (>6 hPa in 3h), heat waves (3+ days
///   above threshold), cold snaps, first/last frost detection
///
/// Reads only persisted collector history. Missing or unavailable history is
/// represented as an empty or error state; it is never synthesized.
/// Wall clock used to decide "today" (live streak) and "this week" (digest).
/// Tests override it with a fixed instant so results do not depend on when,
/// or in which time zone, the suite runs.
final weatherNarrativesClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class WeatherNarrativesNotifier extends Notifier<WeatherNarrativesState> {
  bool _autoAnalyze = true;
  late WeatherHistoryRepository _historyRepository;
  late DateTime Function() _clock;

  @override
  WeatherNarrativesState build() {
    _historyRepository = ref.watch(weatherHistoryRepositoryProvider);
    _clock = ref.watch(weatherNarrativesClockProvider);
    if (_autoAnalyze) {
      Future.microtask(_analyze);
    }
    return const WeatherNarrativesState();
  }

  /// Disable auto-analyze for tests so state is deterministic.
  /// Must be called before the provider is first read.
  @visibleForTesting
  set autoAnalyze(bool value) => _autoAnalyze = value;

  Future<void> _analyze() async {
    state = WeatherNarrativesState(
      narratives: state.narratives,
      isLoading: true,
    );
    try {
      final history = await _historyRepository.loadHistory();
      final now = _clock();
      if (history.isEmpty) {
        state = const WeatherNarrativesState();
        return;
      }

      final provenance = WeatherNarrativeProvenance(
        source: 'local:sensor_readings',
        observationCount: history.length,
        observedFrom: history.first.timestamp,
        observedTo: history.last.timestamp,
      );
      final narratives = <WeatherNarrative>[];

      narratives.addAll(_detectRecords(history, provenance));
      narratives.addAll(_detectPressureEvents(history, provenance));
      narratives.addAll(_detectTemperatureEvents(history, provenance));
      narratives.addAll(_detectStreaks(history, provenance, now));
      narratives.addAll(_generateWeeklyDigest(history, provenance, now));

      narratives.sort((a, b) => b.date.compareTo(a.date));
      state = WeatherNarrativesState(narratives: narratives);
    } catch (error) {
      state = WeatherNarrativesState(
        error: 'Persisted sensor history is unavailable: $error',
      );
    }
  }

  Future<void> refresh() async {
    await _analyze();
  }

  // -- Detection algorithms --

  /// Detect all-time personal records for each metric.
  static List<WeatherNarrative> _detectRecords(
    List<SensorSnapshot> history,
    WeatherNarrativeProvenance provenance,
  ) {
    if (history.isEmpty) return [];

    final narratives = <WeatherNarrative>[];
    double maxTemp = double.negativeInfinity;
    double minTemp = double.infinity;
    int maxHumidity = 0;
    int minHumidity = 100;
    double maxPressure = double.negativeInfinity;
    double minPressure = double.infinity;

    DateTime? maxTempDate, minTempDate;
    DateTime? maxHumidityDate, minHumidityDate;
    DateTime? maxPressureDate, minPressureDate;

    for (final s in history) {
      final temperature = s.temperatureC;
      final humidity = s.humidityPercent;
      if (temperature != null && temperature > maxTemp) {
        maxTemp = temperature;
        maxTempDate = s.timestamp;
      }
      if (temperature != null && temperature < minTemp) {
        minTemp = temperature;
        minTempDate = s.timestamp;
      }
      if (humidity != null && humidity > maxHumidity) {
        maxHumidity = humidity;
        maxHumidityDate = s.timestamp;
      }
      if (humidity != null && humidity < minHumidity) {
        minHumidity = humidity;
        minHumidityDate = s.timestamp;
      }
      if (s.pressureHpa > maxPressure) {
        maxPressure = s.pressureHpa;
        maxPressureDate = s.timestamp;
      }
      if (s.pressureHpa < minPressure) {
        minPressure = s.pressureHpa;
        minPressureDate = s.timestamp;
      }
    }

    if (maxTempDate != null) {
      narratives.add(
        WeatherNarrative(
          type: NarrativeType.record,
          title: 'Hottest recorded: ${maxTemp.toStringAsFixed(1)}°C',
          description: 'Your persisted sensor history contains this all-time high temperature.',
          date: maxTempDate,
          value: maxTemp,
          icon: Icons.local_fire_department,
          provenance: provenance,
        ),
      );
    }

    if (minTempDate != null) {
      narratives.add(
        WeatherNarrative(
          type: NarrativeType.record,
          title: 'Coldest recorded: ${minTemp.toStringAsFixed(1)}°C',
          description:
              'Your station recorded its all-time low temperature. Bundle up!',
          date: minTempDate,
          value: minTemp,
          icon: Icons.ac_unit,
          provenance: provenance,
        ),
      );
    }

    if (maxPressureDate != null) {
      narratives.add(
        WeatherNarrative(
          type: NarrativeType.record,
          title: 'Highest pressure: ${maxPressure.toStringAsFixed(1)} hPa',
          description:
              'A strong high-pressure system was detected. Clear skies ahead!',
          date: maxPressureDate,
          value: maxPressure,
          icon: Icons.compress,
          provenance: provenance,
        ),
      );
    }

    if (minPressureDate != null) {
      narratives.add(
        WeatherNarrative(
          type: NarrativeType.record,
          title: 'Lowest pressure: ${minPressure.toStringAsFixed(1)} hPa',
          description: 'A deep low-pressure system passed through your area.',
          date: minPressureDate,
          value: minPressure,
          icon: Icons.expand,
          provenance: provenance,
        ),
      );
    }

    if (maxHumidityDate != null) {
      narratives.add(
        WeatherNarrative(
          type: NarrativeType.record,
          title: 'Peak humidity: $maxHumidity%',
          description: 'Your station recorded its highest humidity level.',
          date: maxHumidityDate,
          value: maxHumidity.toDouble(),
          icon: Icons.water,
          provenance: provenance,
        ),
      );
    }

    if (minHumidityDate != null) {
      narratives.add(
        WeatherNarrative(
          type: NarrativeType.record,
          title: 'Driest recorded: $minHumidity%',
          description: 'Your station recorded its lowest humidity level.',
          date: minHumidityDate,
          value: minHumidity.toDouble(),
          icon: Icons.dry,
          provenance: provenance,
        ),
      );
    }

    return narratives;
  }

  /// Detect rapid pressure drops (>6 hPa in 3 hours) -- storm indicator.
  static List<WeatherNarrative> _detectPressureEvents(
    List<SensorSnapshot> history,
    WeatherNarrativeProvenance provenance,
  ) {
    if (history.length < 2) return [];

    final narratives = <WeatherNarrative>[];
    const dropThresholdHpa = 6.0;
    const windowDuration = Duration(hours: 3);

    for (var i = 0; i < history.length; i++) {
      final current = history[i];
      // Look back within the 3-hour window
      for (var j = i - 1; j >= 0; j--) {
        final earlier = history[j];
        if (current.timestamp.difference(earlier.timestamp) > windowDuration) {
          break;
        }
        final drop = earlier.pressureHpa - current.pressureHpa;
        if (drop >= dropThresholdHpa) {
          narratives.add(
            WeatherNarrative(
              type: NarrativeType.event,
              title: 'Rapid pressure drop detected',
              description:
                  'Pressure fell ${drop.toStringAsFixed(1)} hPa in ${current.timestamp.difference(earlier.timestamp).inMinutes} minutes. '
                  'This often signals an approaching storm system.',
              date: current.timestamp,
              value: drop,
              icon: Icons.thunderstorm,
              provenance: provenance,
            ),
          );
          // Only report the first event per window
          break;
        }
      }
    }

    // Deduplicate: only keep one pressure event per calendar day. Keyed on
    // the date's own fields (#295): a `difference(Jan 1).inDays` key shifts by
    // the DST offset, splitting one day and merging two across spring-forward.
    final seen = <int>{};
    narratives.removeWhere((n) => !seen.add(_dayNumber(n.date)));

    return narratives;
  }

  /// Detect heat waves (3+ consecutive days above 35°C) and cold snaps
  /// (3+ consecutive days below -5°C), plus first/last frost.
  static List<WeatherNarrative> _detectTemperatureEvents(
    List<SensorSnapshot> history,
    WeatherNarrativeProvenance provenance,
  ) {
    if (history.isEmpty) return [];

    final narratives = <WeatherNarrative>[];

    // Group by date
    final dailyMaxTemp = <DateTime, double>{};
    final dailyMinTemp = <DateTime, double>{};
    for (final s in history) {
      final temperature = s.temperatureC;
      if (temperature == null) continue;
      final date = DateTime(
        s.timestamp.year,
        s.timestamp.month,
        s.timestamp.day,
      );
      final priorMax = dailyMaxTemp[date];
      final priorMin = dailyMinTemp[date];
      dailyMaxTemp[date] = priorMax == null || temperature > priorMax
          ? temperature
          : priorMax;
      dailyMinTemp[date] = priorMin == null || temperature < priorMin
          ? temperature
          : priorMin;
    }

    final sortedDates = dailyMaxTemp.keys.toList()..sort();

    // Heat wave detection: 3+ consecutive CALENDAR days (#295); a day with no
    // temperature reading breaks the run just like a cooler day does.
    int heatStreak = 0;
    int? previousHeatDay;
    for (final date in sortedDates) {
      final day = _dayNumber(date);
      if (previousHeatDay != null && day != previousHeatDay + 1) {
        heatStreak = 0;
      }
      previousHeatDay = day;
      if ((dailyMaxTemp[date] ?? 0) >= 35) {
        heatStreak++;
        if (heatStreak == 3) {
          narratives.add(
            WeatherNarrative(
              type: NarrativeType.event,
              title: 'Heat wave detected!',
              description: 'Your station recorded 3+ consecutive days above 35°C. Stay hydrated and check on neighbors.',
              date: date,
              icon: Icons.whatshot,
              provenance: provenance,
            ),
          );
        }
      } else {
        heatStreak = 0;
      }
    }

    // Cold snap detection: 3+ consecutive CALENDAR days (#295).
    int coldStreak = 0;
    int? previousColdDay;
    for (final date in sortedDates) {
      final day = _dayNumber(date);
      if (previousColdDay != null && day != previousColdDay + 1) {
        coldStreak = 0;
      }
      previousColdDay = day;
      if ((dailyMinTemp[date] ?? 0) <= -5) {
        coldStreak++;
        if (coldStreak == 3) {
          narratives.add(
            WeatherNarrative(
              type: NarrativeType.event,
              title: 'Cold snap detected!',
              description: 'Your station recorded 3+ consecutive days below -5°C. Protect pipes and pets.',
              date: date,
              icon: Icons.severe_cold,
              provenance: provenance,
            ),
          );
        }
      } else {
        coldStreak = 0;
      }
    }

    // First frost detection (first day with min <= 0)
    for (final date in sortedDates) {
      if ((dailyMinTemp[date] ?? 1) <= 0) {
        narratives.add(
          WeatherNarrative(
            type: NarrativeType.event,
            title: 'First frost of the season',
            description:
                'Temperatures dipped to ${dailyMinTemp[date]!.toStringAsFixed(1)}°C. The growing season may be ending.',
            date: date,
            value: dailyMinTemp[date],
            icon: Icons.ac_unit,
            provenance: provenance,
          ),
        );
        break;
      }
    }

    return narratives;
  }

  /// Calendar-day number of [t]'s date (days since 1970-01-01), taken from its
  /// own year/month/day fields. Consecutive dates always differ by exactly 1,
  /// unlike local midnights, which are 23 or 25 hours apart across a DST
  /// change (so `difference(...).inDays` would read 0 or skip a day).
  static int _dayNumber(DateTime t) =>
      DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// The local calendar date (midnight) for a [_dayNumber].
  static DateTime _dateOfDayNumber(int dayNumber) {
    final utc = DateTime.fromMillisecondsSinceEpoch(
      dayNumber * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return DateTime(utc.year, utc.month, utc.day);
  }

  /// Detect consecutive days with at least one reading (uptime streaks).
  static List<WeatherNarrative> _detectStreaks(
    List<SensorSnapshot> history,
    WeatherNarrativeProvenance provenance,
    DateTime now,
  ) {
    if (history.isEmpty) return [];

    final activeDays = <int>{for (final s in history) _dayNumber(s.timestamp)};

    final sortedDays = activeDays.toList()..sort();
    int currentStreak = 1;
    int maxStreak = 1;
    int maxStreakEnd = sortedDays.first;

    for (var i = 1; i < sortedDays.length; i++) {
      if (sortedDays[i] - sortedDays[i - 1] == 1) {
        currentStreak++;
        if (currentStreak > maxStreak) {
          maxStreak = currentStreak;
          maxStreakEnd = sortedDays[i];
        }
      } else {
        currentStreak = 1;
      }
    }

    final narratives = <WeatherNarrative>[];

    if (maxStreak >= 7) {
      narratives.add(
        WeatherNarrative(
          type: NarrativeType.streak,
          title: '$maxStreak-day collection streak!',
          description:
              'Your station has been online for $maxStreak consecutive days. '
              'Consistent data collection is key to improving forecast accuracy.',
          date: _dateOfDayNumber(maxStreakEnd),
          value: maxStreak.toDouble(),
          icon: Icons.local_fire_department,
          provenance: provenance,
        ),
      );
    }

    // Current streak: consecutive active days ending today.
    final today = _dayNumber(now);
    int liveStreak = 0;
    for (var d = today; activeDays.contains(d); d--) {
      liveStreak++;
    }

    if (liveStreak >= 3 && liveStreak != maxStreak) {
      narratives.add(
        WeatherNarrative(
          type: NarrativeType.streak,
          title: 'Currently on a $liveStreak-day streak',
          description:
              'Keep it going! You are $liveStreak days into your current collection streak.',
          date: _dateOfDayNumber(today),
          value: liveStreak.toDouble(),
          icon: Icons.trending_up,
          provenance: provenance,
        ),
      );
    }

    return narratives;
  }

  /// Generate a weekly digest summary.
  static List<WeatherNarrative> _generateWeeklyDigest(
    List<SensorSnapshot> history,
    WeatherNarrativeProvenance provenance,
    DateTime now,
  ) {
    if (history.isEmpty) return [];

    final weekAgo = now.subtract(const Duration(days: 7));
    final weekReadings = history
        .where((s) => s.timestamp.isAfter(weekAgo))
        .toList();

    if (weekReadings.isEmpty) return [];

    final avgPressure =
        weekReadings.map((r) => r.pressureHpa).reduce((a, b) => a + b) /
        weekReadings.length;
    final readingCount = weekReadings.length;

    return [
      WeatherNarrative(
        type: NarrativeType.digest,
        title: 'Weekly digest: $readingCount readings',
        description:
            'This week your device persisted $readingCount pressure observations with an average of '
            '${avgPressure.toStringAsFixed(1)} hPa.',
        date: now,
        icon: Icons.summarize,
        provenance: provenance,
      ),
    ];
  }
}

final weatherNarrativesProvider =
    NotifierProvider<WeatherNarrativesNotifier, WeatherNarrativesState>(
      WeatherNarrativesNotifier.new,
    );
