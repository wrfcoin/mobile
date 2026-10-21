import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/location/location_service.dart';

void main() {
  group('LocationService.anonymize', () {
    test('rounds normal coordinates to the 0.1 degree grid', () {
      expect(LocationService.anonymize(37.77494), 37.8);
    });

    test('preserves equator values near zero', () {
      expect(LocationService.anonymize(0.049), 0.0);
      expect(LocationService.anonymize(-0.051), -0.1);
    });

    test('handles poles without overflowing', () {
      expect(LocationService.anonymize(89.96), 90.0);
      expect(LocationService.anonymize(-89.96), -90.0);
    });

    test('handles antimeridian boundaries', () {
      expect(LocationService.anonymize(179.96), 180.0);
      expect(LocationService.anonymize(-179.96), -180.0);
    });
  });
}
