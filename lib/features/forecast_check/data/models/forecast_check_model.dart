import 'dart:convert';

import '../../../../core/network/public_read.dart';

/// Read models for `GET /api/forecast-verification/summary` (backend
/// observed-verification.ts, checked against the live route on 2026-11-02):
///
/// ```json
/// { "windowDays": 30, "status": "available" | "unavailable", "reason": "…",
///   "counts": { "pending": 0, "scored": 0, "unavailable": 0 },
///   "variables": [ { "variable": "temperature_c",
///     "chain": { "n": 4, "mae": 0.5, "bias": 0.1, "rmse": 0.6 } | null,
///     "vsNoaa": { "n": 3, "chainMae": 0.4, "noaaMae": 0.9, … } | null,
///     "vsNoaaReason": "…" | null } ],
///   "stations": [ … ], "recent": [ <record> ] }
/// ```
///
/// A record: `commitId, stationAlias, modelId, validAt, status ("scored",
/// "pending", "unavailable"), unavailableReason, forecast { variable: number },
/// scores { variable: { forecast, truth, error, noaa { value, error, leadHours }
/// | null } } | null, noaaReason`. Every number is the backend's; a missing one
/// stays null here.
class ForecastCheckSummary {
  const ForecastCheckSummary({
    required this.windowDays,
    required this.available,
    required this.reason,
    required this.scored,
    required this.pending,
    required this.unavailable,
    required this.stationCount,
    required this.variables,
    required this.recent,
  });

  final int? windowDays;
  final bool available;
  final String? reason;
  final int? scored;
  final int? pending;
  final int? unavailable;
  final int? stationCount;
  final List<VariableSkill> variables;
  final List<ForecastRecord> recent;

  factory ForecastCheckSummary.fromJson(Map<String, dynamic> json) {
    final counts = jsonObject(json['counts']);
    final stations = json['stations'];
    return ForecastCheckSummary(
      windowDays: jsonInt(json['windowDays']),
      available: json['status'] == 'available',
      reason: jsonText(json['reason']),
      scored: jsonInt(counts?['scored']),
      pending: jsonInt(counts?['pending']),
      unavailable: jsonInt(counts?['unavailable']),
      stationCount: stations is List ? stations.length : null,
      variables: jsonObjects(json['variables'])
          .map(VariableSkill.fromJson)
          .toList(),
      recent: jsonObjects(json['recent']).map(ForecastRecord.fromJson).toList(),
    );
  }
}

class VariableSkill {
  const VariableSkill({
    required this.variable,
    this.n,
    this.mae,
    this.bias,
    this.noaaN,
    this.chainMaeVsNoaa,
    this.noaaMae,
    this.vsNoaaReason,
  });

  final String variable;
  final int? n;
  final double? mae;
  final double? bias;
  final int? noaaN;
  final double? chainMaeVsNoaa;
  final double? noaaMae;
  final String? vsNoaaReason;

  bool get hasChain => n != null;
  bool get hasNoaa => chainMaeVsNoaa != null && noaaMae != null;

  factory VariableSkill.fromJson(Map<String, dynamic> json) {
    final chain = jsonObject(json['chain']);
    final vs = jsonObject(json['vsNoaa']);
    return VariableSkill(
      variable: jsonText(json['variable']) ?? 'unknown',
      n: jsonInt(chain?['n']),
      mae: jsonDouble(chain?['mae']),
      bias: jsonDouble(chain?['bias']),
      noaaN: jsonInt(vs?['n']),
      chainMaeVsNoaa: jsonDouble(vs?['chainMae']),
      noaaMae: jsonDouble(vs?['noaaMae']),
      vsNoaaReason: jsonText(json['vsNoaaReason']),
    );
  }
}

class VariableScore {
  const VariableScore({
    this.forecast,
    this.truth,
    this.error,
    this.noaaValue,
    this.noaaError,
    this.noaaLeadHours,
  });

  final double? forecast;
  final double? truth;
  final double? error;
  final double? noaaValue;
  final double? noaaError;
  final double? noaaLeadHours;

  bool get hasNoaa => noaaValue != null;

  factory VariableScore.fromJson(Map<String, dynamic> json) {
    final noaa = jsonObject(json['noaa']);
    return VariableScore(
      forecast: jsonDouble(json['forecast']),
      truth: jsonDouble(json['truth']),
      error: jsonDouble(json['error']),
      noaaValue: jsonDouble(noaa?['value']),
      noaaError: jsonDouble(noaa?['error']),
      noaaLeadHours: jsonDouble(noaa?['leadHours']),
    );
  }
}

class ForecastRecord {
  const ForecastRecord({
    required this.commitId,
    required this.stationAlias,
    required this.modelId,
    required this.validAt,
    required this.status,
    required this.unavailableReason,
    required this.forecast,
    required this.scores,
    required this.noaaReason,
  });

  final String commitId;
  final String? stationAlias;
  final String? modelId;
  final String? validAt;
  final String status;
  final String? unavailableReason;
  final Map<String, double> forecast;
  final Map<String, VariableScore> scores;
  final String? noaaReason;

  /// The variable a row shows: temperature when scored, as on the website.
  String get mainVariable {
    if (scores.containsKey('temperature_c')) return 'temperature_c';
    if (scores.isNotEmpty) return scores.keys.first;
    if (forecast.isNotEmpty) return forecast.keys.first;
    return 'temperature_c';
  }

  factory ForecastRecord.fromJson(Map<String, dynamic> json) {
    final forecast = <String, double>{};
    jsonObject(json['forecast'])?.forEach((key, value) {
      final number = jsonDouble(value);
      if (number != null) forecast[key] = number;
    });
    final scores = <String, VariableScore>{};
    jsonObject(json['scores'])?.forEach((key, value) {
      final score = jsonObject(value);
      if (score != null) scores[key] = VariableScore.fromJson(score);
    });
    return ForecastRecord(
      commitId: jsonText(json['commitId']) ?? '',
      stationAlias: jsonText(json['stationAlias']),
      modelId: jsonText(json['modelId']),
      validAt: jsonText(json['validAt']),
      status: jsonText(json['status']) ?? 'unknown',
      unavailableReason: jsonText(json['unavailableReason']),
      forecast: forecast,
      scores: scores,
      noaaReason: jsonText(json['noaaReason']),
    );
  }
}

/// The body of `POST /api/forecast-verification/forecasts`: a forecast kit
/// record, which proves itself because it hashes to the chain commit id. It
/// needs no login and carries no personal data.
class ForecastHandIn {
  const ForecastHandIn({
    required this.commitId,
    required this.nonce,
    required this.timestamp,
    required this.data,
  });

  final String commitId;
  final String nonce;
  final int timestamp;
  final String data;

  Map<String, Object> toJson() => {
    'commitId': commitId,
    'nonce': nonce,
    'timestamp': timestamp,
    'data': data,
  };

  static final _commitId = RegExp(r'^[0-9a-f]{64}$');
  static const _maxSafeInteger = 9007199254740991;

  /// commit.json gives the id, nonce and timestamp; data.json is sent exactly
  /// as written. Returns the record, or the reason it cannot be sent. The same
  /// checks as the website's form.
  static (ForecastHandIn?, String?) fromFiles(
    String commitText,
    String dataText,
  ) {
    Object? commit;
    try {
      commit = jsonDecode(commitText);
    } on FormatException {
      return (null, 'commit.json is not valid JSON.');
    }
    final id = commit is Map ? commit['commit_id'] : null;
    final commitId = id is String ? id.trim().toLowerCase() : '';
    if (commit is! Map || !_commitId.hasMatch(commitId)) {
      return (null, 'commit.json has no 64-character commit_id.');
    }
    final nonce = commit['nonce'];
    final timestamp = commit['timestamp'];
    if (nonce is! String ||
        timestamp is! int ||
        timestamp.abs() > _maxSafeInteger) {
      return (null, 'commit.json needs its nonce and timestamp.');
    }
    final data = dataText.replaceAll('\r\n', '\n').trim();
    if (data.isEmpty) return (null, 'Paste the contents of data.json.');
    return (
      ForecastHandIn(
        commitId: commitId,
        nonce: nonce,
        timestamp: timestamp,
        data: data,
      ),
      null,
    );
  }
}
