import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'certificate_pin_validator.dart';
import 'pinnable_ca_certificates.dart';
import 'tls_pin_configuration.dart';

/// Creates an [IOHttpClientAdapter] that trusts only the pinned CAs.
/// Returns null only for the visibly NON_RELEASE developer profile.
HttpClientAdapter? createPinnedAdapter() {
  final configuration = TlsPinConfiguration.fromEnvironment();
  final pins = configuration.validatedPins();
  if (pins.isEmpty) return null;

  // Built once, before any request: a bad pin fails the app at start-up.
  final context = pinnedSecurityContext(pins);
  return IOHttpClientAdapter(createHttpClient: () => pinnedHttpClient(context));
}

/// A TLS context whose ONLY trust anchors are the bundled CA certificates
/// whose public key matches one of [pins] (SPKI SHA-256).
///
/// The platform trust store is not loaded. The TLS stack (BoringSSL) builds
/// the chain the server presents up to a pinned certificate and verifies every
/// signature, the validity dates and the host name; an intermediate is
/// accepted as an anchor, so pinning the issuing CA works without its root.
/// A chain that never reaches a pinned key fails the handshake.
SecurityContext pinnedSecurityContext(
  List<String> pins, {
  List<PinnableCaCertificate> catalog = pinnableCaCertificates,
}) {
  final context = SecurityContext(withTrustedRoots: false);
  for (final der in pinnedTrustAnchors(pins, catalog: catalog)) {
    context.setTrustedCertificatesBytes(utf8.encode(certificatePem(der)));
  }
  return context;
}

/// An [HttpClient] on [context] that never overrides a failed verification.
HttpClient pinnedHttpClient(SecurityContext context) =>
    HttpClient(context: context)..badCertificateCallback = (_, _, _) => false;
