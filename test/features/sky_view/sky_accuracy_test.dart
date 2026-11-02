import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_accuracy.dart';

void main() {
  test('Android status alone', () {
    expect(rotationVectorAccuracy(3, -1), SkyAccuracy.good);
    expect(rotationVectorAccuracy(2, -1), SkyAccuracy.fair);
    expect(rotationVectorAccuracy(1, -1), SkyAccuracy.poor);
    expect(rotationVectorAccuracy(0, -1), SkyAccuracy.poor);
    expect(rotationVectorAccuracy(-1, -1), SkyAccuracy.poor);
    expect(rotationVectorAccuracy(99, -1), SkyAccuracy.unknown);
  });
  test('the worse of status and estimated heading accuracy wins', () {
    expect(rotationVectorAccuracy(3, 0.1), SkyAccuracy.good); // 5.7 degrees
    expect(rotationVectorAccuracy(3, 0.3), SkyAccuracy.fair); // 17 degrees
    expect(rotationVectorAccuracy(3, 0.6), SkyAccuracy.poor); // 34 degrees
    expect(rotationVectorAccuracy(1, 0.1), SkyAccuracy.poor);
    expect(rotationVectorAccuracy(99, 0.1), SkyAccuracy.good);
  });
  test('a missing heading estimate does not count as a perfect one', () {
    expect(rotationVectorAccuracy(2, 0), SkyAccuracy.fair);
    expect(rotationVectorAccuracy(2, double.nan), SkyAccuracy.fair);
  });
  test('only poor asks for a figure-eight', () {
    expect(SkyAccuracy.values.where((a) => a.low).toList(), [SkyAccuracy.poor]);
  });
  test(
    'fallback never claims good, and flags a field that is not the Earth\'s',
    () {
      expect(fallbackAccuracy(45), SkyAccuracy.fair);
      expect(fallbackAccuracy(90), SkyAccuracy.poor);
      expect(fallbackAccuracy(15), SkyAccuracy.poor);
    },
  );
}
