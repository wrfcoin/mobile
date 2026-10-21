import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/api/tls_pin_configuration.dart';

const pinA =
    '00:01:02:03:04:05:06:07:08:09:0A:0B:0C:0D:0E:0F:'
    '10:11:12:13:14:15:16:17:18:19:1A:1B:1C:1D:1E:1F';
const pinB =
    '20:21:22:23:24:25:26:27:28:29:2A:2B:2C:2D:2E:2F:'
    '30:31:32:33:34:35:36:37:38:39:3A:3B:3C:3D:3E:3F';

TlsPinConfiguration configuration({
  String profile = tlsPublicReleaseProfile,
  String current = pinA,
  String next = '',
  bool product = true,
}) => TlsPinConfiguration(
  profile: profile,
  currentPin: current,
  nextPin: next,
  isProductBuild: product,
);

void main() {
  group('release TLS pin configuration', () {
    test('accepts a current pin and one bounded rotation pin', () {
      expect(configuration(next: pinB).validatedPins(), [pinA, pinB]);
    });

    test('rejects missing, placeholder, and malformed release pins', () {
      for (final current in ['', 'CONFIGURE_VIA_DART_DEFINE', 'AA:BB']) {
        expect(
          () => configuration(current: current).validatedPins(),
          throwsStateError,
        );
      }
    });

    test('rejects duplicate current and next pins', () {
      expect(
        () => configuration(next: pinA.toLowerCase()).validatedPins(),
        throwsStateError,
      );
    });

    test('product builds cannot use the developer trust-store fallback', () {
      final config = configuration(profile: tlsDeveloperProfile, current: '');
      expect(config.releaseClassification, 'NON_RELEASE');
      expect(config.validatedPins, throwsStateError);
    });

    test('developer fallback is explicit and visibly NON_RELEASE', () {
      final config = configuration(
        profile: tlsDeveloperProfile,
        current: '',
        product: false,
      );
      expect(config.releaseClassification, 'NON_RELEASE');
      expect(config.validatedPins(), isEmpty);
    });
  });
}
