import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/api/tls_pin_configuration.dart';

const releaseSet = 'cloudflare-universal-v1';
const pinA =
    '00:01:02:03:04:05:06:07:08:09:0A:0B:0C:0D:0E:0F:'
    '10:11:12:13:14:15:16:17:18:19:1A:1B:1C:1D:1E:1F';
const pinB = '202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F';

TlsPinConfiguration configuration({
  String profile = tlsPublicReleaseProfile,
  String pinSet = releaseSet,
  bool product = true,
  Map<String, List<String>> pinSets = tlsPinSets,
}) => TlsPinConfiguration(
  profile: profile,
  pinSet: pinSet,
  isProductBuild: product,
  pinSets: pinSets,
);

Matcher stateErrorContaining(String text) => throwsA(
  isA<StateError>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  group('release TLS pin set', () {
    test('the release set names ten distinct, well-formed pins', () {
      final pins = configuration().validatedPins();
      expect(pins, hasLength(10));
      expect(pins.map(normalizeCertificatePin).toSet(), hasLength(10));
      expect(pins.every(isValidSha256CertificatePin), isTrue);
    });

    test('a release build with no pin set stops', () {
      for (final name in ['', '   ']) {
        expect(
          () => configuration(pinSet: name).validatedPins(),
          stateErrorContaining('requires TLS_PIN_SET'),
        );
      }
    });

    test('an unknown or empty pin set stops', () {
      for (final name in ['cloudflare-universal-v0', 'CONFIGURE_ME', 'gts']) {
        expect(
          () => configuration(pinSet: name).validatedPins(),
          stateErrorContaining('Unknown or empty TLS pin set'),
        );
      }
      expect(
        () => configuration(
          pinSet: 'empty',
          pinSets: const {'empty': []},
        ).validatedPins(),
        stateErrorContaining('Unknown or empty TLS pin set'),
      );
    });

    test('a set with a malformed or repeated pin stops', () {
      for (final pins in [
        [pinA, 'AA:BB'],
        [pinA, 'CONFIGURE_VIA_DART_DEFINE'],
        [pinA, pinB, pinA.replaceAll(':', '').toLowerCase()],
      ]) {
        expect(
          () =>
              configuration(pinSet: 'x', pinSets: {'x': pins}).validatedPins(),
          throwsStateError,
        );
      }
      expect(
        configuration(
          pinSet: 'x',
          pinSets: const {
            'x': [pinA, pinB],
          },
        ).validatedPins(),
        [pinA, pinB],
      );
    });

    test('product builds cannot use the developer trust-store fallback', () {
      final config = configuration(profile: tlsDeveloperProfile, pinSet: '');
      expect(config.releaseClassification, 'NON_RELEASE');
      expect(config.validatedPins, throwsStateError);
    });

    test('developer fallback is explicit and visibly NON_RELEASE', () {
      final config = configuration(
        profile: tlsDeveloperProfile,
        pinSet: '',
        product: false,
      );
      expect(config.releaseClassification, 'NON_RELEASE');
      expect(config.validatedPins(), isEmpty);
    });

    test('a developer build may opt in to the release set', () {
      final config = configuration(
        profile: tlsDeveloperProfile,
        product: false,
      );
      expect(config.validatedPins(), hasLength(10));
    });

    test('an unknown profile stops', () {
      expect(
        () => configuration(profile: 'staging').validatedPins(),
        stateErrorContaining('Unknown TLS security profile'),
      );
    });
  });
}
