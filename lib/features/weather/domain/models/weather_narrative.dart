import 'package:flutter/material.dart';

/// Types of weather narratives that can be generated from sensor data.
enum NarrativeType {
  /// Personal all-time highs/lows.
  record,

  /// Weather events (rapid pressure drops, heat waves, cold snaps, frost).
  event,

  /// Consecutive days of activity or conditions.
  streak,

  /// Weekly summary digest.
  digest,
}

/// Identifies the persisted observations used to derive a narrative.
class WeatherNarrativeProvenance {
  final String source;
  final int observationCount;
  final DateTime observedFrom;
  final DateTime observedTo;

  const WeatherNarrativeProvenance({
    required this.source,
    required this.observationCount,
    required this.observedFrom,
    required this.observedTo,
  });
}

/// A single weather narrative generated from sensor data analysis.
class WeatherNarrative {
  final NarrativeType type;
  final String title;
  final String description;
  final DateTime date;
  final double? value;
  final IconData icon;
  final WeatherNarrativeProvenance? provenance;

  const WeatherNarrative({
    required this.type,
    required this.title,
    required this.description,
    required this.date,
    this.value,
    required this.icon,
    this.provenance,
  });

  /// Stories without an attributable persisted source cannot be shared as
  /// network facts.
  bool get isShareable => provenance != null;

  /// Whether this narrative represents a new personal record.
  bool get isRecord => type == NarrativeType.record;

  /// Whether this narrative represents a weather event.
  bool get isEvent => type == NarrativeType.event;
}
