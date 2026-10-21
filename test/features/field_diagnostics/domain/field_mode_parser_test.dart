import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/field_diagnostics/domain/field_diagnostics_transport.dart';
import 'package:wrfcoin_mobile/features/field_diagnostics/domain/field_mode_parser.dart';

void main() {
  const transport = FieldDiagnosticTransports.manual;
  const frameHex = '40 26:01-1b aa 00 34 12';

  test('parses frame hex and verifies an HMAC signature when available', () {
    const sharedSecret = 'field-stage-key';
    final canonical = frameHex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
    final signature = Hmac(sha256, utf8.encode(sharedSecret))
        .convert(utf8.encode(canonical))
        .toString();

    final result = FieldModeCaptureParser.parse(
      transport: transport,
      frameHex: frameHex,
      signatureHex: signature,
      sharedSecret: sharedSecret,
    );

    expect(result.hasFrame, isTrue);
    expect(result.frameHeader, isNotNull);
    expect(result.frameHeader!.deviceAddress, 'aa1b0126');
    expect(result.authState, FieldCaptureAuthState.verified);
  });

  test('flags invalid signatures explicitly', () {
    const sharedSecret = 'field-stage-key';

    final result = FieldModeCaptureParser.parse(
      transport: transport,
      frameHex: frameHex,
      signatureHex: 'f0' * 32,
      sharedSecret: sharedSecret,
    );

    expect(result.authState, FieldCaptureAuthState.invalidSignature);
  });

  test('keeps capture as unverified when signature inputs are missing', () {
    final result = FieldModeCaptureParser.parse(
      transport: transport,
      frameHex: frameHex,
      signatureHex: null,
      sharedSecret: 'field-stage-key',
    );

    expect(result.hasFrame, isTrue);
    expect(result.authState, FieldCaptureAuthState.unverified);
  });

  test('returns parse-failure before auth checks when payload is malformed', () {
    final result = FieldModeCaptureParser.parse(
      transport: transport,
      frameHex: '40 26 01',
      signatureHex: '12',
      sharedSecret: 'field-stage-key',
    );

    expect(result.hasFrame, isFalse);
    expect(result.authState, FieldCaptureAuthState.parseFailure);
  });
}

