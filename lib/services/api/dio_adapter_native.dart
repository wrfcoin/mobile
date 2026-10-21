import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'certificate_pin_validator.dart';
import 'tls_pin_configuration.dart';

/// Creates an [IOHttpClientAdapter] with certificate pinning enabled.
/// Returns null only for the visibly NON_RELEASE developer profile.
HttpClientAdapter? createPinnedAdapter() {
  final configuration = TlsPinConfiguration.fromEnvironment();
  final pins = configuration.validatedPins();
  if (pins.isEmpty) return null;

  return IOHttpClientAdapter(
    validateCertificate: (certificate, host, port) {
      if (certificate == null) return false; // Fail closed
      final derBytes = certificate.der;
      final digest = sha256.convert(derBytes);
      return certificateMatchesPins(Uint8List.fromList(digest.bytes), pins);
    },
  );
}
