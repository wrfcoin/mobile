import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/domain/cloud_observation.dart';

void main() {
  test(
    'formats a user-confirmed observation without claiming ML inference',
    () {
      expect(
        cloudObservationDescription(
          genus: CloudGenus.cumulonimbus,
          description: 'Developing over the ridge.',
        ),
        'Cloud observation (user confirmed): Cumulonimbus. '
        'Developing over the ridge.',
      );
    },
  );

  test('keeps a useful observation when no free-form note is supplied', () {
    expect(
      cloudObservationDescription(
        genus: CloudGenus.uncertain,
        description: ' ',
      ),
      'Cloud observation (user confirmed): Other or uncertain.',
    );
  });
}
