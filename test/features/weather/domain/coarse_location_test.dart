import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';

void main() {
  test('rounds to the nearest 0.1° and prints one decimal', () {
    final cases = <(double, double, String)>[
      (44.98765, -93.26543, '45.0,-93.3'),
      (37.775, -122.419, '37.8,-122.4'),
      (-33.8688, 151.2093, '-33.9,151.2'),
      (0.04, -0.04, '0.0,0.0'),
      (-0.04, -0.001, '0.0,0.0'),
      (89.99, 179.99, '90.0,180.0'),
      (12.0, -7.0, '12.0,-7.0'),
    ];
    for (final (lat, lon, expected) in cases) {
      expect(CoarseLocation.round(lat, lon).pathSegment, expected);
    }
  });

  test('no digit beyond the first decimal reaches the path segment', () {
    final segment = CoarseLocation.round(
      51.123456789,
      -0.987654321,
    ).pathSegment;
    expect(segment, '51.1,-1.0');
    expect(RegExp(r'\.\d{2}').hasMatch(segment), isFalse);
  });

  test('the stored fields hold the rounded values', () {
    final location = CoarseLocation.round(44.98765, -93.26543);
    expect(location.latitude, 45.0);
    expect(location.longitude, -93.3);
  });

  test('a position rounding to zero is +0.0, never -0.0', () {
    final location = CoarseLocation.round(-0.04, -0.001);
    expect(location.latitude.isNegative, isFalse);
    expect(location.longitude.isNegative, isFalse);
  });

  test('equal rounded positions are equal', () {
    expect(
      CoarseLocation.round(45.01, -93.31),
      CoarseLocation.round(44.96, -93.26),
    );
  });
}
