const String tlsPublicReleaseProfile = 'public-release';
const String tlsDeveloperProfile = 'developer';

/// The pin set a release build ships: the SPKI SHA-256 pins of every CA root
/// Cloudflare Universal SSL may chain wrfcoin.com's certificate to (primary or
/// backup). Selected with `--dart-define=TLS_PIN_SET=<name>`.
///
/// Each pin must match a root bundled in pinnable_ca_certificates.dart, or the
/// app stops at start-up. scripts/validate-release-tls-pins.sh reads the set
/// names from the `'<name>': [` lines below, so keep that shape. A changed set
/// gets a new name (bump the suffix), so a build record names exactly the
/// roots it trusts. See docs/RELEASING.md#tls-pins.
const Map<String, List<String>> tlsPinSets = {
  'cloudflare-universal-v1': [
    // Google Trust Services
    '871a9194f4eed5b312ff40c84c1d524aed2f778bbff25f138cf81f680a7adc67', // GTS Root R1
    '9847e5653e5e9e847516e5cb818606aa7544a19be67fd7366d506988e8d84347', // GTS Root R4
    // Let's Encrypt
    '0b9fa5a59eed715c26c1020c711b4f6ec42d58b0015e14337a39dad301c5afc3', // ISRG Root X1
    '762195c225586ee6c0237456e2107dc54f1efc21f61a792ebd515913cce68332', // ISRG Root X2
    // Sectigo
    '2021917e98263945c859c43f1d73cb4139053c414fa03ca3bc7ee88614298f3b', // USERTrust ECC
    'c784333d20bcd742b9fdc3236f4e509b8937070e73067e254dd3bf9c45bf4dde', // USERTrust RSA
    'b0b56335468561f5bb9fa12d801784a633a572705d34f32b643445dfa8b005d1', // Sectigo E46
    '0e8bb18bbeefb381be21bfc1a206d317298462ad104855f04a0542699708d3d4', // Sectigo R46
    // SSL.com
    '1bf00d5c8f13c094dd17e00504cf0888850f12fd067fa1f92c0fdbf60b86e321', // TLS ECC 2022
    '2bcf553a66f570900ddd32ba6dfe1ecc06c9182d662dc1b60e1f7b767c2bdd54', // TLS RSA 2022
  ],
};

/// Release TLS pins: the named pin set of SPKI SHA-256 pins of CA roots
/// (see certificate_pin_validator.dart and docs/RELEASING.md#tls-pins).
class TlsPinConfiguration {
  const TlsPinConfiguration({
    required this.profile,
    required this.pinSet,
    required this.isProductBuild,
    this.pinSets = tlsPinSets,
  });

  factory TlsPinConfiguration.fromEnvironment() => const TlsPinConfiguration(
    profile: String.fromEnvironment(
      'TLS_SECURITY_PROFILE',
      defaultValue: tlsDeveloperProfile,
    ),
    pinSet: String.fromEnvironment('TLS_PIN_SET'),
    isProductBuild: bool.fromEnvironment('dart.vm.product'),
  );

  final String profile;

  /// The name of the pin set (a key of [pinSets]); empty means none.
  final String pinSet;
  final bool isProductBuild;
  final Map<String, List<String>> pinSets;

  String get releaseClassification =>
      profile == tlsPublicReleaseProfile ? 'PUBLIC_RELEASE' : 'NON_RELEASE';

  /// The pins of the configured set. Empty only for a developer build with no
  /// set (platform trust store). Throws [StateError] when a public release has
  /// no set, the set is unknown or empty, or a pin is malformed or repeated.
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

    final name = pinSet.trim();
    if (name.isEmpty) {
      if (profile == tlsPublicReleaseProfile) {
        throw StateError('Public release requires TLS_PIN_SET');
      }
      return const [];
    }
    final pins = pinSets[name];
    if (pins == null || pins.isEmpty) {
      throw StateError('Unknown or empty TLS pin set: $name');
    }
    final seen = <String>{};
    for (final pin in pins) {
      if (!isValidSha256CertificatePin(pin)) {
        throw StateError('TLS certificate pin is malformed or a placeholder');
      }
      if (!seen.add(normalizeCertificatePin(pin))) {
        throw StateError('TLS pin set $name repeats a pin');
      }
    }
    return List.unmodifiable(pins);
  }
}

String normalizeCertificatePin(String pin) =>
    pin.replaceAll(':', '').toUpperCase();

bool isValidSha256CertificatePin(String pin) {
  final value = pin.trim().toUpperCase();
  return RegExp(r'^[0-9A-F]{64}$').hasMatch(value) ||
      RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$').hasMatch(value);
}
