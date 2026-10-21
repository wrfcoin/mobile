import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/domain/cloud_classification.dart';
import 'package:wrfcoin_mobile/features/collector/domain/cloud_observation.dart';

void main() {
  test(
    'parses a high-confidence model payload into stable suggestion model',
    () {
      final suggestion = CloudClassificationParser.parseModelOutput({
        'modelVersion': 'ml-cloud-v1',
        'predictions': [
          {'label': 'cumulonimbus', 'confidence': 0.91},
        ],
      });

      expect(suggestion, isNotNull);
      expect(suggestion!.primary.genus.name, CloudGenus.cumulonimbus.name);
      expect(suggestion.primary.confidence, closeTo(0.91, 0.0001));
      expect(suggestion.isHighConfidence, true);
      expect(suggestion.modelVersion, 'ml-cloud-v1');
    },
  );

  test('normalizes confidence values reported on 0-100 scale', () {
    final suggestion = CloudClassificationParser.parseModelOutput({
      'predictions': [
        {'label': 'cumulus', 'confidence': 91},
      ],
    });

    expect(suggestion, isNotNull);
    expect(suggestion!.primary.confidence, closeTo(0.91, 0.0001));
    expect(suggestion.isHighConfidence, true);
  });

  test('rejects impossible confidence values', () {
    expect(
      CloudClassificationParser.parseModelOutput({
        'predictions': [
          {'label': 'cumulus', 'confidence': -0.1},
        ],
      }),
      isNull,
    );

    expect(
      CloudClassificationParser.parseModelOutput({
        'predictions': [
          {'label': 'cumulus', 'confidence': 140},
        ],
      }),
      isNull,
    );
  });

  test('returns null when the parser does not have a supported label', () {
    final suggestion = CloudClassificationParser.parseModelOutput({
      'predictions': [
        {'label': 'not_a_real_class', 'confidence': 0.99},
      ],
    });

    expect(suggestion, isNull);
  });

  test('normalizes labels for existing map variants', () {
    expect(
      CloudClassificationParser.parseLabel('Clear Sky'),
      CloudGenus.clearSky,
    );
    expect(
      CloudClassificationParser.parseLabel('haze_or_fog'),
      CloudGenus.hazeOrFog,
    );
  });
}
