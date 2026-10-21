import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/api/certificate_pin_validator.dart';

void main() {
  group('certificateMatchesPins', () {
    // Build a deterministic 32-byte SHA-256 digest and its colon-hex form.
    final sampleSha256 = Uint8List.fromList(List.generate(32, (i) => i));
    final sampleHex = List.generate(
      32,
      (i) => i.toRadixString(16).padLeft(2, '0').toUpperCase(),
    ).join(':');

    test('returns true when cert fingerprint matches a pin', () {
      expect(certificateMatchesPins(sampleSha256, [sampleHex]), isTrue);
    });

    test('returns true when cert matches one of multiple pins', () {
      expect(
        certificateMatchesPins(sampleSha256, ['XX:YY:ZZ', sampleHex]),
        isTrue,
      );
    });

    test('returns false when no pin matches', () {
      expect(certificateMatchesPins(sampleSha256, ['AA:BB:CC']), isFalse);
    });

    test('returns false for null cert bytes', () {
      expect(certificateMatchesPins(null, [sampleHex]), isFalse);
    });

    test('returns false for empty cert bytes', () {
      expect(certificateMatchesPins(Uint8List(0), [sampleHex]), isFalse);
    });

    test('comparison is case-insensitive', () {
      expect(
        certificateMatchesPins(sampleSha256, [sampleHex.toLowerCase()]),
        isTrue,
      );
    });

    test('returns false when pins list is empty', () {
      expect(certificateMatchesPins(sampleSha256, []), isFalse);
    });
  });
}
