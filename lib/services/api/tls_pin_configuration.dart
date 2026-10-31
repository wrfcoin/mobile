const String tlsPublicReleaseProfile = 'public-release';
const String tlsDeveloperProfile = 'developer';

/// Release TLS pins: SPKI SHA-256 pins of CA certificates in the API's chain
/// (see certificate_pin_validator.dart and docs/RELEASING.md#tls-pins).
class TlsPinConfiguration {
  const TlsPinConfiguration({
    required this.profile,
    required this.currentPin,
    required this.nextPin,
    required this.isProductBuild,
  });

  factory TlsPinConfiguration.fromEnvironment() => const TlsPinConfiguration(
    profile: String.fromEnvironment(
      'TLS_SECURITY_PROFILE',
      defaultValue: tlsDeveloperProfile,
    ),
    currentPin: String.fromEnvironment('TLS_PIN_SHA256_CURRENT'),
    nextPin: String.fromEnvironment('TLS_PIN_SHA256_NEXT'),
    isProductBuild: bool.fromEnvironment('dart.vm.product'),
  );

  final String profile;
  final String currentPin;
  final String nextPin;
  final bool isProductBuild;

  String get releaseClassification =>
      profile == tlsPublicReleaseProfile ? 'PUBLIC_RELEASE' : 'NON_RELEASE';

  List<String> validatedPins() {
    if (profile != tlsPublicReleaseProfile && profile != tlsDeveloperProfile) {
      throw StateError('Unknown TLS security profile: $profile');
    }
    if (isProductBuild && profile != tlsPublicReleaseProfile) {
      throw StateError(
        'Product builds require TLS_SECURITY_PROFILE=$tlsPublicReleaseProfile; '
        'current classification is $releaseClassification',
      );
    }

    final candidates = [currentPin.trim(), nextPin.trim()];
    final supplied = candidates.where((pin) => pin.isNotEmpty).toList();
    for (final pin in supplied) {
      if (!isValidSha256CertificatePin(pin)) {
        throw StateError('TLS certificate pin is malformed or a placeholder');
      }
    }

    if (profile == tlsPublicReleaseProfile && supplied.isEmpty) {
      throw StateError('Public release requires a current TLS certificate pin');
    }
    if (profile == tlsPublicReleaseProfile && currentPin.trim().isEmpty) {
      throw StateError('Public release requires TLS_PIN_SHA256_CURRENT');
    }
    if (supplied.length == 2 &&
        normalizeCertificatePin(supplied[0]) ==
            normalizeCertificatePin(supplied[1])) {
      throw StateError('Current and next TLS pins must be distinct');
    }
    return supplied;
  }
}

String normalizeCertificatePin(String pin) =>
    pin.replaceAll(':', '').toUpperCase();

bool isValidSha256CertificatePin(String pin) {
  final value = pin.trim().toUpperCase();
  return RegExp(r'^[0-9A-F]{64}$').hasMatch(value) ||
      RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$').hasMatch(value);
}
