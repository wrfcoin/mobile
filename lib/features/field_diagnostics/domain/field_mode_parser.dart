import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'field_diagnostics_transport.dart';
import 'lorawan_frame.dart';

enum FieldCaptureAuthState {
  unverified,
  verified,
  invalidSignature,
  invalidSignatureFormat,
  parseFailure,
}

class FieldModeCaptureResult {
  const FieldModeCaptureResult({
    required this.transportId,
    required this.transportName,
    required this.inputHex,
    required this.canonicalHex,
    required this.authState,
    required this.canSyncToDiagnostics,
    this.frameHeader,
    this.errorMessage,
  });

  final String transportId;
  final String transportName;
  final String inputHex;
  final String canonicalHex;
  final FieldCaptureAuthState authState;
  final bool canSyncToDiagnostics;
  final LoraWanFrameHeader? frameHeader;
  final String? errorMessage;

  bool get hasFrame => frameHeader != null;
}

class FieldModeCaptureParser {
  const FieldModeCaptureParser._();

  static const _hexPattern = r'^[0-9a-fA-F]+$';

  static FieldModeCaptureResult parse({
    required FieldDiagnosticTransport transport,
    required String frameHex,
    String? signatureHex,
    String? sharedSecret,
  }) {
    final canonicalHex = _normalizeHex(frameHex);

    final parsedHeader = LoraWanFrameHeader.tryParseHex(frameHex);
    if (parsedHeader == null) {
      return FieldModeCaptureResult(
        transportId: transport.id,
        transportName: transport.name,
        inputHex: frameHex,
        canonicalHex: canonicalHex,
        authState: FieldCaptureAuthState.parseFailure,
        canSyncToDiagnostics: false,
        frameHeader: null,
        errorMessage: 'Unable to parse a valid LoRaWAN header from this frame.',
      );
    }

    if (!transport.isRuntimeVerified) {
      return FieldModeCaptureResult(
        transportId: transport.id,
        transportName: transport.name,
        inputHex: frameHex,
        canonicalHex: canonicalHex,
        authState: FieldCaptureAuthState.unverified,
        canSyncToDiagnostics: false,
        frameHeader: parsedHeader,
        errorMessage:
            'Transport runtime is not currently implemented for live capture.',
      );
    }

    if (!transport.supportsAuthenticatedCapture) {
      return FieldModeCaptureResult(
        transportId: transport.id,
        transportName: transport.name,
        inputHex: frameHex,
        canonicalHex: canonicalHex,
        authState: FieldCaptureAuthState.unverified,
        canSyncToDiagnostics: false,
        frameHeader: parsedHeader,
        errorMessage:
            'Authentication contract is not defined for this transport.',
      );
    }

    if (sharedSecret == null || sharedSecret.trim().isEmpty) {
      return FieldModeCaptureResult(
        transportId: transport.id,
        transportName: transport.name,
        inputHex: frameHex,
        canonicalHex: canonicalHex,
        authState: FieldCaptureAuthState.unverified,
        canSyncToDiagnostics: false,
        frameHeader: parsedHeader,
        errorMessage: 'No shared secret provided; capture is parsed as diagnostic-only and unverified.',
      );
    }

    if (signatureHex == null || signatureHex.trim().isEmpty) {
      return FieldModeCaptureResult(
        transportId: transport.id,
        transportName: transport.name,
        inputHex: frameHex,
        canonicalHex: canonicalHex,
        authState: FieldCaptureAuthState.unverified,
        canSyncToDiagnostics: false,
        frameHeader: parsedHeader,
        errorMessage: 'No signature supplied; capture is parsed as diagnostic-only and unverified.',
      );
    }

    final normalizedSignature = _normalizeHex(signatureHex);
    if (!_isValidHex16Bytes(normalizedSignature)) {
      return FieldModeCaptureResult(
        transportId: transport.id,
        transportName: transport.name,
        inputHex: frameHex,
        canonicalHex: canonicalHex,
        authState: FieldCaptureAuthState.invalidSignatureFormat,
        canSyncToDiagnostics: false,
        frameHeader: parsedHeader,
        errorMessage: 'Signature is not valid hex (expected 64 hex chars).',
      );
    }

    final expected = _expectedSignature(
      secret: sharedSecret,
      frameHex: canonicalHex,
    );

    if (expected == normalizedSignature) {
      return FieldModeCaptureResult(
        transportId: transport.id,
        transportName: transport.name,
        inputHex: frameHex,
        canonicalHex: canonicalHex,
        authState: FieldCaptureAuthState.verified,
        canSyncToDiagnostics: true,
        frameHeader: parsedHeader,
      );
    }

    return FieldModeCaptureResult(
      transportId: transport.id,
      transportName: transport.name,
      inputHex: frameHex,
      canonicalHex: canonicalHex,
      authState: FieldCaptureAuthState.invalidSignature,
      canSyncToDiagnostics: false,
      frameHeader: parsedHeader,
      errorMessage: 'Signature does not authenticate this capture.',
    );
  }

  static String _expectedSignature({
    required String secret,
    required String frameHex,
  }) {
    final key = utf8.encode(secret.trim());
    final bytes = utf8.encode(frameHex);
    return Hmac(sha256, key).convert(bytes).toString();
  }

  static String _normalizeHex(String hex) =>
      hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();

  static bool _isValidHex16Bytes(String value) =>
      RegExp(_hexPattern).hasMatch(value) && value.length == 64;
}
