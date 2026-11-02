import '../../../../core/network/public_read.dart';

/// Read models for the weekly forecast competition (backend
/// competition-routes.ts, checked against the live routes on 2026-11-02).
///
/// `GET /api/competitions`:
/// ```json
/// { "success": true, "current": "2026-W45",
///   "weeks": [ { "week": "2026-W45", "from": "<iso>", "until": "<iso>",
///     "title": "…", "status": "open" | "scoring" | "final",
///     "entrants": 0 | null, "forecasts": "0" | null, "leaders": [ <row> ] } ] }
/// ```
///
/// `GET /api/competitions/current` and `/api/competitions/<ISO week>`:
/// ```json
/// { "success": true,
///   "competition": { "week": "…", "from": "<iso>", "until": "<iso>",
///     "title": "…", "status": "open",
///     "rule": { "id": "…", "points": "…", "ties": "…", "prizes": "…", "week": "…" },
///     "final": { "finalizedAt": "<iso>", "throughHeight": "123",
///                "throughHash": "…" } | null },
///   "asOf": { "height": "11598", "hash": "…", "time": "<iso>",
///             "checkedAt": "<iso>" } | null,
///   "coverage": { … } | null, "entrants": 0, "forecasts": "0",
///   "rows": [ <row> ], "you": <row> | null, "limit": 50 }
/// ```
///
/// A row: `rank (int), points, forecasts (digit strings), firstAt, lastAt,
/// profileKey, shortAddress, address (null unless it is your own), isYou`.
/// Points only: no WRF, no stake, and an address is all that identifies anyone.
class CompetitionRow {
  const CompetitionRow({
    required this.rank,
    required this.points,
    required this.forecasts,
    required this.lastAt,
    required this.shownAddress,
    required this.isYou,
  });

  final int? rank;
  final String? points;
  final String? forecasts;
  final String? lastAt;
  final String? shownAddress;
  final bool isYou;

  factory CompetitionRow.fromJson(Map<String, dynamic> json) => CompetitionRow(
    rank: jsonInt(json['rank']),
    points: jsonText(json['points']),
    forecasts: jsonText(json['forecasts']),
    lastAt: jsonText(json['lastAt']),
    shownAddress: jsonText(json['address']) ?? jsonText(json['shortAddress']),
    isYou: json['isYou'] == true,
  );
}

class CompetitionWeek {
  const CompetitionWeek({
    required this.week,
    required this.from,
    required this.until,
    required this.status,
    required this.leaders,
  });

  final String week;
  final String? from;
  final String? until;
  final String? status;
  final List<CompetitionRow> leaders;

  factory CompetitionWeek.fromJson(Map<String, dynamic> json) =>
      CompetitionWeek(
        week: jsonText(json['week']) ?? '',
        from: jsonText(json['from']),
        until: jsonText(json['until']),
        status: jsonText(json['status']),
        leaders: jsonObjects(json['leaders'])
            .map(CompetitionRow.fromJson)
            .toList(),
      );
}

class CompetitionList {
  const CompetitionList({required this.current, required this.weeks});

  final String? current;
  final List<CompetitionWeek> weeks;

  factory CompetitionList.fromJson(Map<String, dynamic> json) =>
      CompetitionList(
        current: jsonText(json['current']),
        weeks: jsonObjects(json['weeks'])
            .map(CompetitionWeek.fromJson)
            .toList(),
      );
}

class CompetitionRule {
  const CompetitionRule({
    required this.points,
    required this.ties,
    required this.week,
    required this.prizes,
  });

  final String? points;
  final String? ties;
  final String? week;
  final String? prizes;
}

class CompetitionStandings {
  const CompetitionStandings({
    required this.week,
    required this.from,
    required this.until,
    required this.status,
    required this.rule,
    required this.finalThroughHeight,
    required this.finalizedAt,
    required this.isFinal,
    required this.asOfHeight,
    required this.asOfTime,
    required this.entrants,
    required this.forecasts,
    required this.rows,
    required this.you,
  });

  final String week;
  final String? from;
  final String? until;
  final String? status;
  final CompetitionRule? rule;
  final bool isFinal;
  final String? finalThroughHeight;
  final String? finalizedAt;
  final String? asOfHeight;
  final String? asOfTime;
  final int? entrants;
  final String? forecasts;
  final List<CompetitionRow> rows;
  final CompetitionRow? you;

  /// Your own row when it is outside the rows shown.
  CompetitionRow? get youBelow =>
      you != null && !rows.any((row) => row.isYou) ? you : null;

  factory CompetitionStandings.fromJson(Map<String, dynamic> json) {
    final competition = jsonObject(json['competition']);
    if (competition == null) {
      throw const FormatException('A standings answer names its competition.');
    }
    final rule = jsonObject(competition['rule']);
    final finalInfo = jsonObject(competition['final']);
    final asOf = jsonObject(json['asOf']);
    final you = jsonObject(json['you']);
    return CompetitionStandings(
      week: jsonText(competition['week']) ?? '',
      from: jsonText(competition['from']),
      until: jsonText(competition['until']),
      status: jsonText(competition['status']),
      rule: rule == null
          ? null
          : CompetitionRule(
              points: jsonText(rule['points']),
              ties: jsonText(rule['ties']),
              week: jsonText(rule['week']),
              prizes: jsonText(rule['prizes']),
            ),
      isFinal: finalInfo != null,
      finalThroughHeight: jsonText(finalInfo?['throughHeight']),
      finalizedAt: jsonText(finalInfo?['finalizedAt']),
      asOfHeight: jsonText(asOf?['height']),
      asOfTime: jsonText(asOf?['time']),
      entrants: jsonInt(json['entrants']),
      forecasts: jsonText(json['forecasts']),
      rows: jsonObjects(json['rows']).map(CompetitionRow.fromJson).toList(),
      you: you == null ? null : CompetitionRow.fromJson(you),
    );
  }
}

/// "Week 45" from "2026-W45"; the label itself if it has another shape.
String competitionWeekNumber(String week) {
  final number = RegExp(r'^\d{4}-W(\d{2})$').firstMatch(week)?.group(1);
  return number == null ? week : 'Week ${int.parse(number)}';
}

/// "2 days 4 h" until [until], or null once it has passed or is unreadable.
String? competitionTimeLeft(String? until, {DateTime? now}) {
  final end = until == null ? null : DateTime.tryParse(until);
  if (end == null) return null;
  final left = end.difference(now ?? DateTime.now());
  if (left <= Duration.zero) return null;
  final hours = left.inHours;
  final days = hours ~/ 24;
  if (days >= 1) return '$days day${days == 1 ? '' : 's'} ${hours % 24} h';
  final minutes = left.inMinutes % 60;
  final shown = minutes < 1 ? 1 : minutes;
  return hours >= 1 ? '$hours h $shown min' : '$shown min';
}
