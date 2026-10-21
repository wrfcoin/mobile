import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wrfcoin_mobile/features/weather/domain/models/weather_narrative.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_narratives_provider.dart';

class _FakeHistoryRepository implements WeatherHistoryRepository {
  final List<SensorSnapshot> history;
  final Object? failure;

  const _FakeHistoryRepository(this.history) : failure = null;
  const _FakeHistoryRepository.failure(this.failure) : history = const [];

  @override
  Future<List<SensorSnapshot>> loadHistory() async {
    if (failure != null) throw failure!;
    return history;
  }
}

/// Fixed analysis instant. Every test pins the notifier's clock and builds its
/// fixture from the same instant, so no result depends on when (or in which
/// time zone) the suite runs. The old wall-clock fixture failed between 00:00
/// and 02:00 local time, and across a DST change.
final DateTime _defaultNow = DateTime(2026, 9, 24, 12);

ProviderContainer _container(
  WeatherHistoryRepository repository, {
  DateTime? now,
}) {
  final pinned = now ?? _defaultNow;
  final container = ProviderContainer(
    overrides: [
      weatherHistoryRepositoryProvider.overrideWithValue(repository),
      weatherNarrativesClockProvider.overrideWithValue(() => pinned),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Eight consecutive LOCAL calendar days ending on [now]'s date: one noon
/// reading on each of the 7 previous days (built with the calendar
/// constructor, so a DST change or month end cannot shift a reading onto a
/// neighbouring date), plus a rapid pressure drop at the start of today.
/// [now] must be at or after 00:20 local so today's readings are not in the
/// future.
List<SensorSnapshot> _persistedFixture({
  double firstPressure = 1015,
  DateTime? now,
}) {
  final anchor = now ?? _defaultNow;
  final todayStart = DateTime(anchor.year, anchor.month, anchor.day);
  return [
    for (var day = 7; day >= 1; day--)
      SensorSnapshot(
        readingId: 100 + day,
        timestamp: DateTime(anchor.year, anchor.month, anchor.day - day, 12),
        pressureHpa: 1011 + day.toDouble(),
      ),
    SensorSnapshot(
      readingId: 200,
      timestamp: todayStart,
      pressureHpa: firstPressure,
    ),
    SensorSnapshot(
      readingId: 201,
      timestamp: todayStart.add(const Duration(minutes: 20)),
      pressureHpa: 1007,
    ),
  ];
}

Future<WeatherNarrativesState> _refresh(ProviderContainer container) async {
  await container.read(weatherNarrativesProvider.notifier).refresh();
  return container.read(weatherNarrativesProvider);
}

void main() {
  group('WeatherNarrative provenance', () {
    test('unattributed narratives are not shareable', () {
      final narrative = WeatherNarrative(
        type: NarrativeType.record,
        title: 'Unattributed',
        description: 'No persisted source',
        date: DateTime(2026, 9, 17),
        icon: Icons.star,
      );

      expect(narrative.isShareable, isFalse);
    });
  });

  group('WeatherNarrativesNotifier', () {
    test('derives stories only from injected persisted history', () async {
      final container = _container(_FakeHistoryRepository(_persistedFixture()));

      final state = await _refresh(container);

      expect(state.error, isNull);
      expect(state.narratives, isNotEmpty);
      expect(
        state.narratives.any(
          (narrative) => narrative.title == 'Highest pressure: 1018.0 hPa',
        ),
        isTrue,
      );
      expect(
        state.narratives.any(
          (narrative) => narrative.title == 'Rapid pressure drop detected',
        ),
        isTrue,
      );
      expect(
        state.narratives.any(
          (narrative) => narrative.title == '8-day collection streak!',
        ),
        isTrue,
      );
      expect(
        state.narratives.every(
          (narrative) =>
              narrative.provenance?.source == 'local:sensor_readings' &&
              narrative.provenance?.observationCount == 9 &&
              narrative.isShareable,
        ),
        isTrue,
      );
      expect(
        state.narratives.where((narrative) => narrative.isRecord).length,
        2,
        reason: 'Persisted pressure cannot fabricate temperature or humidity records.',
      );
    });

    // Boundary instants (local time of the machine running the suite; the
    // DST cases bite in zones that observe them, e.g. TZ=America/Los_Angeles
    // or Europe/London, and are harmless elsewhere).
    final boundaries = <String, DateTime>{
      'midday': DateTime(2026, 9, 24, 12),
      'just after local midnight (old fixture failed 00:00-02:00)':
          DateTime(2026, 9, 24, 0, 30),
      'just before local midnight': DateTime(2026, 9, 24, 23, 59),
      'month end rollover (Sep 30 -> Oct 1)': DateTime(2026, 10, 1, 0, 30),
      'year end rollover': DateTime(2027, 1, 1, 0, 30),
      'leap day window (Feb 29 2028)': DateTime(2028, 3, 1, 0, 30),
      'US DST spring-forward inside window (Mar 8 2026)':
          DateTime(2026, 3, 10, 12),
      'US DST spring-forward day itself': DateTime(2026, 3, 8, 12),
      'US DST fall-back inside window (Nov 1 2026)': DateTime(2026, 11, 2, 0, 30),
      'EU DST spring-forward inside window (Mar 29 2026)':
          DateTime(2026, 3, 31, 12),
      'EU DST fall-back inside window (Oct 25 2026)': DateTime(2026, 10, 27, 0, 30),
      // Southern hemisphere (bites under TZ=America/Santiago): spring-forward
      // happens AT midnight, so 2026-09-06 has no 00:00 at all
      // (DateTime(2026, 9, 6) is 01:00 there) and the next midnight is only
      // 23 h later.
      'Chile DST spring-forward inside window (Sep 6 2026, midnight skipped)':
          DateTime(2026, 9, 8, 12),
      'Chile DST spring-forward day itself': DateTime(2026, 9, 6, 12),
      'UTC midnight': DateTime.utc(2026, 9, 24).toLocal(),
      'one minute before UTC midnight': DateTime.utc(2026, 9, 23, 23, 59)
          .toLocal(),
    };
    for (final entry in boundaries.entries) {
      test('8-day streak is stable at boundary: ${entry.key}', () async {
        var now = entry.value;
        // The fixture puts two readings at 00:00-00:20 local today.
        if (now.hour == 0 && now.minute < 20) {
          now = DateTime(now.year, now.month, now.day, 0, 20);
        }
        final state = await _refresh(
          _container(
            _FakeHistoryRepository(_persistedFixture(now: now)),
            now: now,
          ),
        );

        final streaks = state.narratives
            .where((n) => n.type == NarrativeType.streak)
            .map((n) => n.title)
            .toList();
        expect(streaks, ['8-day collection streak!'], reason: 'now=$now');
        final streak = state.narratives.firstWhere(
          (n) => n.title == '8-day collection streak!',
        );
        expect(
          streak.date,
          DateTime(now.year, now.month, now.day),
          reason: 'streak ends on the local date of now=$now',
        );
      });
    }

    test('live streak counts back from the pinned today across DST', () async {
      // An older 6-day run (Feb 21-26), a gap, then a live 5-day run
      // (Mar 6-10) that straddles US spring-forward on Mar 8. The live streak
      // must count all 5 days (it differs from the 6-day max, so it is shown).
      final now = DateTime(2026, 3, 10, 12);
      final history = [
        for (var day = 17; day >= 12; day--)
          SensorSnapshot(
            readingId: 300 + day,
            timestamp: DateTime(2026, 3, 10 - day, 12),
            pressureHpa: 1010,
          ),
        for (var day = 4; day >= 0; day--)
          SensorSnapshot(
            readingId: 400 + day,
            timestamp: DateTime(2026, 3, 10 - day, 12),
            pressureHpa: 1010,
          ),
      ];
      final state = await _refresh(
        _container(_FakeHistoryRepository(history), now: now),
      );
      final titles = state.narratives.map((n) => n.title).toList();
      expect(titles, contains('Currently on a 5-day streak'));
    });

    // Fall-back: the live streak steps back across a 25 h day. Each case has
    // an older, longer run so live != max and the live narrative is emitted
    // (and asserted) rather than suppressed.
    final fallBackLiveCases = <String, DateTime>{
      // Bites under TZ=America/Santiago: 2026-04-04 is 25 h long.
      'Chile DST fall-back (Apr 5 2026)': DateTime(2026, 4, 7, 12),
      // Bites under TZ=America/Los_Angeles: 2026-11-01 is 25 h long.
      'US DST fall-back (Nov 1 2026)': DateTime(2026, 11, 3, 12),
    };
    for (final entry in fallBackLiveCases.entries) {
      test('live streak counts back across ${entry.key}', () async {
        final now = entry.value;
        final history = [
          // Older 6-day run ending 11 days before now.
          for (var day = 16; day >= 11; day--)
            SensorSnapshot(
              readingId: 500 + day,
              timestamp: DateTime(now.year, now.month, now.day - day, 12),
              pressureHpa: 1010,
            ),
          // Live 5-day run ending today, straddling the 25 h day.
          for (var day = 4; day >= 0; day--)
            SensorSnapshot(
              readingId: 600 + day,
              timestamp: DateTime(now.year, now.month, now.day - day, 12),
              pressureHpa: 1010,
            ),
        ];
        final state = await _refresh(
          _container(_FakeHistoryRepository(history), now: now),
        );
        final live = state.narratives.where(
          (n) => n.title.startsWith('Currently on a'),
        );
        expect(
          live.map((n) => n.title).toList(),
          ['Currently on a 5-day streak'],
          reason: 'now=$now',
        );
        expect(live.single.date, DateTime(now.year, now.month, now.day));
      });
    }

    test(
      'source fixture mutation changes the derived record and event',
      () async {
        final baseline = await _refresh(
          _container(_FakeHistoryRepository(_persistedFixture())),
        );
        final mutated = await _refresh(
          _container(
            _FakeHistoryRepository(_persistedFixture(firstPressure: 1025)),
          ),
        );

        final baselineRecord = baseline.narratives.firstWhere(
          (narrative) => narrative.title.startsWith('Highest pressure:'),
        );
        final mutatedRecord = mutated.narratives.firstWhere(
          (narrative) => narrative.title.startsWith('Highest pressure:'),
        );
        final baselineEvent = baseline.narratives.firstWhere(
          (narrative) => narrative.title == 'Rapid pressure drop detected',
        );
        final mutatedEvent = mutated.narratives.firstWhere(
          (narrative) => narrative.title == 'Rapid pressure drop detected',
        );

        expect(mutatedRecord.value, isNot(baselineRecord.value));
        expect(mutatedEvent.value, isNot(baselineEvent.value));
      },
    );

    test('empty persisted history remains honestly empty', () async {
      final state = await _refresh(
        _container(const _FakeHistoryRepository([])),
      );

      expect(state.narratives, isEmpty);
      expect(state.error, isNull);
      expect(state.isLoading, isFalse);
    });

    test('repository failure becomes an explicit unavailable state', () async {
      final state = await _refresh(
        _container(const _FakeHistoryRepository.failure('database offline')),
      );

      expect(state.narratives, isEmpty);
      expect(state.error, contains('database offline'));
      expect(state.isLoading, isFalse);
    });
  });

  // #295 leftovers: pressure-event de-dup must key on the calendar date (not
  // a DST-shifted hour count from Jan 1), and heat-wave / cold-snap runs must
  // be consecutive CALENDAR days, not merely consecutive days that have data.
  group('WeatherNarrativesNotifier date keys (#295)', () {
    Future<WeatherNarrativesState> analyze(List<SensorSnapshot> history) {
      return _refresh(
        _container(
          _FakeHistoryRepository(history),
          now: DateTime(2027, 1, 1, 12),
        ),
      );
    }

    List<String> titles(WeatherNarrativesState s, String title) =>
        s.narratives.map((n) => n.title).where((t) => t == title).toList();

    // A rapid drop shortly after local midnight on each of two consecutive
    // dates. The old key (inDays since Jan 1) loses an hour after a
    // spring-forward, so the second date's 00:30 event got the first date's
    // key and was dropped as a "same day" duplicate.
    final pressurePairs = <String, List<DateTime>>{
      'US spring-forward (Mar 8 -> Mar 9 2026)': [
        DateTime(2026, 3, 8),
        DateTime(2026, 3, 9),
      ],
      'EU spring-forward (Mar 29 -> Mar 30 2026)': [
        DateTime(2026, 3, 29),
        DateTime(2026, 3, 30),
      ],
      'Chile spring-forward (Sep 6 -> Sep 7 2026)': [
        DateTime(2026, 9, 6),
        DateTime(2026, 9, 7),
      ],
      'ordinary dates (Jun 10 -> Jun 11 2026)': [
        DateTime(2026, 6, 10),
        DateTime(2026, 6, 11),
      ],
    };
    for (final entry in pressurePairs.entries) {
      test('one pressure event per calendar day across ${entry.key}', () async {
        final history = <SensorSnapshot>[];
        var id = 700;
        for (final day in entry.value) {
          final start = DateTime(day.year, day.month, day.day);
          history
            ..add(SensorSnapshot(readingId: id++, timestamp: start, pressureHpa: 1020))
            ..add(
              SensorSnapshot(
                readingId: id++,
                timestamp: start.add(const Duration(minutes: 30)),
                pressureHpa: 1010,
              ),
            );
        }
        final state = await analyze(history);
        expect(
          titles(state, 'Rapid pressure drop detected'),
          hasLength(2),
          reason: 'two drops on two different calendar dates',
        );
      });
    }

    test('two drops on the SAME calendar day still de-duplicate to one', () async {
      final start = DateTime(2026, 6, 10);
      final history = [
        SensorSnapshot(readingId: 1, timestamp: start, pressureHpa: 1020),
        SensorSnapshot(readingId: 2, timestamp: start.add(const Duration(minutes: 30)), pressureHpa: 1010),
        SensorSnapshot(readingId: 3, timestamp: start.add(const Duration(hours: 12)), pressureHpa: 1020),
        SensorSnapshot(readingId: 4, timestamp: start.add(const Duration(hours: 12, minutes: 30)), pressureHpa: 1010),
      ];
      final state = await analyze(history);
      expect(titles(state, 'Rapid pressure drop detected'), hasLength(1));
    });

    // Southern hemisphere (#298 review): Jan 1 is in DST there, so after the
    // autumn fall-back (Santiago Apr 5, Lord Howe Apr 5 2026) the old
    // `difference(Jan 1).inDays` key runs AHEAD, and a late-evening drop was
    // keyed to the next day, splitting one calendar day into two events for
    // the whole winter. Pin it with an 00:30 + 23:30 pair on the same date.
    final sameDayLatePairs = <String, DateTime>{
      'southern winter (Apr 7 2026, after Santiago/Lord Howe fall-back)':
          DateTime(2026, 4, 7),
      'southern mid-winter (Jul 15 2026)': DateTime(2026, 7, 15),
      'northern summer (Jul 16 2026, summer time in LA/London)':
          DateTime(2026, 7, 16),
      'no-DST season everywhere-ish (Jan 20 2026)': DateTime(2026, 1, 20),
    };
    for (final entry in sameDayLatePairs.entries) {
      test('00:30 and 23:30 drops on one date de-duplicate to one: ${entry.key}',
          () async {
        final d = entry.value;
        DateTime at(int h, int m) => DateTime(d.year, d.month, d.day, h, m);
        final state = await analyze([
          SensorSnapshot(readingId: 1, timestamp: at(0, 0), pressureHpa: 1020),
          SensorSnapshot(readingId: 2, timestamp: at(0, 30), pressureHpa: 1010),
          SensorSnapshot(readingId: 3, timestamp: at(23, 0), pressureHpa: 1020),
          SensorSnapshot(readingId: 4, timestamp: at(23, 30), pressureHpa: 1010),
        ]);
        expect(titles(state, 'Rapid pressure drop detected'), hasLength(1));
      });
    }

    SensorSnapshot temp(int id, DateTime day, double c) => SensorSnapshot(
          readingId: id,
          timestamp: DateTime(day.year, day.month, day.day, 15),
          temperatureC: c,
          pressureHpa: 1013,
        );

    test('a missing day breaks a heat wave (hot, hot, [no data], hot)', () async {
      final state = await analyze([
        temp(1, DateTime(2026, 7, 1), 36),
        temp(2, DateTime(2026, 7, 2), 37),
        temp(3, DateTime(2026, 7, 4), 38),
      ]);
      expect(titles(state, 'Heat wave detected!'), isEmpty);
    });

    test('a missing day breaks a cold snap (cold, cold, [no data], cold)', () async {
      final state = await analyze([
        temp(1, DateTime(2026, 1, 5), -6),
        temp(2, DateTime(2026, 1, 6), -7),
        temp(3, DateTime(2026, 1, 8), -8),
      ]);
      expect(titles(state, 'Cold snap detected!'), isEmpty);
    });

    // Positive controls: three truly consecutive days still count, including
    // runs that straddle a DST change (Chile Sep 6 2026 has no local midnight).
    final consecutiveRuns = <String, DateTime>{
      'ordinary': DateTime(2026, 7, 1),
      'across US spring-forward': DateTime(2026, 3, 7),
      'across Chile spring-forward (midnight skipped)': DateTime(2026, 9, 5),
      'across month end': DateTime(2026, 7, 30),
    };
    for (final entry in consecutiveRuns.entries) {
      test('three consecutive hot days are a heat wave (${entry.key})', () async {
        final d = entry.value;
        final state = await analyze([
          for (var k = 0; k < 3; k++) temp(10 + k, DateTime(d.year, d.month, d.day + k), 36),
        ]);
        expect(titles(state, 'Heat wave detected!'), hasLength(1));
      });
      test('three consecutive cold days are a cold snap (${entry.key})', () async {
        final d = entry.value;
        final state = await analyze([
          for (var k = 0; k < 3; k++) temp(20 + k, DateTime(d.year, d.month, d.day + k), -6),
        ]);
        expect(titles(state, 'Cold snap detected!'), hasLength(1));
      });
    }
  });

  group('SensorSnapshot', () {
    test('represents pressure-only persisted collector readings', () {
      final snapshot = SensorSnapshot(
        readingId: 42,
        timestamp: DateTime(2026, 9, 17, 12),
        pressureHpa: 1013.2,
      );

      expect(snapshot.readingId, 42);
      expect(snapshot.temperatureC, isNull);
      expect(snapshot.humidityPercent, isNull);
      expect(snapshot.pressureHpa, 1013.2);
    });
  });
}
