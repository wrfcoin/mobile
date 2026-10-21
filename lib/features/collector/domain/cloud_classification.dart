import 'dart:io';

import 'cloud_observation.dart';

const double _kHighConfidenceThreshold = 0.78;

enum CloudClassifierSource { onDevice, unavailable }

class CloudClassificationPrediction {
  const CloudClassificationPrediction({
    required this.genus,
    required this.confidence,
  });

  final CloudGenus genus;
  final double confidence;

  Map<String, dynamic> toJson() {
    return {'genus': genus.name, 'confidence': confidence};
  }
}

class CloudClassificationSuggestion {
  const CloudClassificationSuggestion({
    required this.primary,
    required this.source,
    this.modelVersion,
  });

  final CloudClassificationPrediction primary;
  final CloudClassifierSource source;
  final String? modelVersion;

  bool get isHighConfidence => primary.confidence >= _kHighConfidenceThreshold;
}

abstract class CloudClassifier {
  const CloudClassifier();

  bool get isDeviceAvailable;

  Future<CloudClassificationSuggestion?> classify(File imageFile);
}

class NoOpCloudClassifier implements CloudClassifier {
  const NoOpCloudClassifier();

  @override
  bool get isDeviceAvailable => false;

  @override
  Future<CloudClassificationSuggestion?> classify(File imageFile) async => null;
}

class CloudClassificationParser {
  static final Map<String, CloudGenus> _labelMap = <String, CloudGenus>{
    'cirrus': CloudGenus.cirrus,
    'cirrocumulus': CloudGenus.cirrocumulus,
    'cirrostratus': CloudGenus.cirrostratus,
    'altocumulus': CloudGenus.altocumulus,
    'altostratus': CloudGenus.altostratus,
    'nimbostratus': CloudGenus.nimbostratus,
    'stratocumulus': CloudGenus.stratocumulus,
    'stratus': CloudGenus.stratus,
    'cumulus': CloudGenus.cumulus,
    'cumulonimbus': CloudGenus.cumulonimbus,
    'clear_sky': CloudGenus.clearSky,
    'clear sky': CloudGenus.clearSky,
    'haze_or_fog': CloudGenus.hazeOrFog,
    'haze or fog': CloudGenus.hazeOrFog,
    'other': CloudGenus.uncertain,
    'other_or_uncertain': CloudGenus.uncertain,
    'uncertain': CloudGenus.uncertain,
  };

  static String normalizeLabel(String raw) {
    return raw.trim().toLowerCase();
  }

  static CloudGenus? parseLabel(String raw) {
    final normalized = normalizeLabel(raw);
    return _labelMap[normalized];
  }

  static CloudClassificationSuggestion? parseModelOutput(
    Map<String, dynamic> raw,
  ) {
    final predictions = raw['predictions'];
    if (predictions is! List || predictions.isEmpty) {
      return null;
    }

    final best = predictions.first;
    if (best is! Map<String, dynamic>) return null;

    final label = best['label'];
    final confidence = best['confidence'];
    final modelVersion = raw['modelVersion'];

    if (label is! String || confidence is! num) return null;

    final genus = parseLabel(label);
    if (genus == null) return null;

    final normalizedConfidence = _normalizeConfidence(confidence);
    if (normalizedConfidence == null) return null;

    return CloudClassificationSuggestion(
      primary: CloudClassificationPrediction(
        genus: genus,
        confidence: normalizedConfidence,
      ),
      source: CloudClassifierSource.onDevice,
      modelVersion: modelVersion is String && modelVersion.isNotEmpty
          ? modelVersion
          : null,
    );
  }

  static double? _normalizeConfidence(num confidence) {
    final normalized = confidence.toDouble();
    if (normalized.isNaN || normalized.isInfinite) {
      return null;
    }

    if (normalized >= 0 && normalized <= 1) {
      return normalized;
    }

    if (normalized > 1 && normalized <= 100) {
      return normalized / 100;
    }

    return null;
  }
}
