import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'pinnable_ca_certificates.dart';
import 'tls_pin_configuration.dart';

/// SPKI pinning: a pin is the SHA-256 of a certificate's DER
/// SubjectPublicKeyInfo, written as 64 hex digits (colons optional, any case).
/// It names a public key, so it survives the certificate being reissued for
/// the same key. Release builds pin a CA (the issuing intermediate and a
/// backup such as its root), never the 90-day leaf.

/// The DER SubjectPublicKeyInfo of an X.509 certificate [certificateDer].
///
/// Throws [FormatException] when [certificateDer] is not a DER certificate.
Uint8List subjectPublicKeyInfoDer(Uint8List certificateDer) {
  final certificate = _Der(certificateDer).readSequence();
  final tbs = _Der(certificate.content).readSequence();
  final fields = _Der(tbs.content);
  // version [0] EXPLICIT is optional (absent means v1).
  if (fields.peekTag() == 0xa0) fields.read();
  fields.read(); // serialNumber
  fields.read(); // signature AlgorithmIdentifier
  fields.read(); // issuer
  fields.read(); // validity
  fields.read(); // subject
  final spki = fields.read();
  if (spki.tag != 0x30) {
    throw const FormatException('certificate has no SubjectPublicKeyInfo');
  }
  return spki.encoded;
}

/// The SPKI SHA-256 pin of [certificateDer], as 64 uppercase hex digits.
String spkiSha256Pin(Uint8List certificateDer) => sha256
    .convert(subjectPublicKeyInfoDer(certificateDer))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();

/// True when [certificateDer]'s public key matches any of [pins].
bool certificateMatchesSpkiPins(Uint8List? certificateDer, List<String> pins) {
  if (certificateDer == null || certificateDer.isEmpty) return false;
  final String pin;
  try {
    pin = spkiSha256Pin(certificateDer);
  } on FormatException {
    return false;
  }
  return pins.any((candidate) => normalizeCertificatePin(candidate) == pin);
}

/// The certificates (DER) from [catalog] whose public key matches one of
/// [pins]. These become the only trust anchors of the pinned TLS context.
///
/// Fails closed: throws [StateError] when [pins] is empty or any pin matches
/// no certificate in [catalog], because such a pin could never be enforced.
List<Uint8List> pinnedTrustAnchors(
  List<String> pins, {
  List<PinnableCaCertificate> catalog = pinnableCaCertificates,
}) {
  if (pins.isEmpty) {
    throw StateError('TLS pinning requires at least one SPKI pin');
  }
  final certificates = [
    for (final entry in catalog) base64.decode(entry.derBase64),
  ];
  final anchors = <Uint8List>[];
  for (final pin in pins) {
    final matches = certificates
        .where((der) => certificateMatchesSpkiPins(der, [pin]))
        .toList();
    if (matches.isEmpty) {
      throw StateError(
        'TLS pin ${normalizeCertificatePin(pin)} matches no bundled CA '
        'certificate (lib/services/api/pinnable_ca_certificates.dart)',
      );
    }
    anchors.addAll(matches);
  }
  return anchors;
}

/// [der] as a PEM certificate block, the form SecurityContext accepts.
String certificatePem(Uint8List der) {
  final body = base64.encode(der);
  final lines = [
    for (var i = 0; i < body.length; i += 64)
      body.substring(i, i + 64 > body.length ? body.length : i + 64),
  ];
  return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n'
      '-----END CERTIFICATE-----\n';
}

class _Tlv {
  const _Tlv(this.tag, this.content, this.encoded);

  final int tag;
  final Uint8List content;
  final Uint8List encoded;
}

/// Minimal DER reader: single-byte tags, definite lengths only.
class _Der {
  _Der(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int peekTag() {
    if (_offset >= _bytes.length) {
      throw const FormatException('truncated DER');
    }
    return _bytes[_offset];
  }

  _Tlv readSequence() {
    final tlv = read();
    if (tlv.tag != 0x30) throw const FormatException('expected DER SEQUENCE');
    return tlv;
  }

  _Tlv read() {
    final start = _offset;
    final tag = peekTag();
    if (tag & 0x1f == 0x1f) {
      throw const FormatException('multi-byte DER tags are not supported');
    }
    _offset++;
    if (_offset >= _bytes.length) throw const FormatException('truncated DER');
    var length = _bytes[_offset++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || _offset + count > _bytes.length) {
        throw const FormatException('unsupported DER length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _bytes[_offset++];
      }
    }
    final end = _offset + length;
    if (end > _bytes.length) throw const FormatException('truncated DER');
    final content = Uint8List.sublistView(_bytes, _offset, end);
    _offset = end;
    return _Tlv(tag, content, Uint8List.sublistView(_bytes, start, end));
  }
}
