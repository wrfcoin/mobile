import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/domain/cloud_observation.dart';
import 'package:wrfcoin_mobile/features/collector/domain/imagery_submission_payload.dart';

void main() {
  test(
    'keeps local classifier output out of the existing imagery contract',
    () {
      final payload = buildImagerySubmissionPayload(
        category: 'cloud_formation',
        cloudGenus: CloudGenus.cumulus,
        description: 'manual confirmation',
        latitude: 45.5,
        longitude: -122.6,
      );

      expect(payload, {
        'dataType': 'imagery',
        'category': 'cloud_formation',
        'description': cloudObservationDescription(
          genus: CloudGenus.cumulus,
          description: 'manual confirmation',
        ),
        'latitude': 45.5,
        'longitude': -122.6,
      });
      expect(payload, isNot(contains('ml_classification')));
    },
  );

  test('omits absent coordinates instead of emitting null entries', () {
    final payload = buildImagerySubmissionPayload(
      category: 'other',
      cloudGenus: CloudGenus.cumulus,
      description: 'no coordinates available',
    );

    // Exact-map equality: an emitted `'latitude': null` fails here, which is
    // the behaviour the null-aware markers in the builder are responsible for.
    expect(payload, {
      'dataType': 'imagery',
      'category': 'other',
      'description': 'no coordinates available',
    });
    expect(payload.containsKey('latitude'), isFalse);
    expect(payload.containsKey('longitude'), isFalse);
  });

  test('omits only the missing coordinate when one is supplied', () {
    final payload = buildImagerySubmissionPayload(
      category: 'other',
      cloudGenus: CloudGenus.cumulus,
      description: 'partial fix',
      latitude: 45.5,
    );

    expect(payload['latitude'], 45.5);
    expect(payload.containsKey('longitude'), isFalse);
  });
}
