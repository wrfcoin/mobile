import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'transparent_transfer_authorization.dart';

import 'transfer_signing_domain.dart';

export 'transfer_signing_domain.dart';

/// Signs transfer authorizations with the wallet's ed25519 key.
///
/// The key is the 32-byte SLIP-0010 master seed stored by [KeyManager] for
/// `ed25519-slip10` wallets (core4#3234, mobile#263).
class Ed25519TransferSigner {
  Ed25519TransferSigner._(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;

  /// 32-byte ed25519 public key.
  final Uint8List publicKey;

  static Future<Ed25519TransferSigner> fromSeedHex(String seedHex) async {
    final clean = seedHex.trim().toLowerCase().replaceFirst('0x', '');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(clean)) {
      throw ArgumentError('ed25519 seed must be 32 bytes of hex');
    }
    final seed = <int>[
      for (var i = 0; i < clean.length; i += 2)
        int.parse(clean.substring(i, i + 2), radix: 16),
    ];
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = await pair.extractPublicKey();
    return Ed25519TransferSigner._(pair, Uint8List.fromList(publicKey.bytes));
  }

  Future<Uint8List> sign(List<int> message) async {
    final signature = await Ed25519().sign(message, keyPair: _keyPair);
    return Uint8List.fromList(signature.bytes);
  }
}

final RegExp _positiveInteger = RegExp(r'^[1-9]\d*$');
final RegExp _unsignedInteger = RegExp(r'^\d+$');

/// Largest amount backend `parseBaseUnits` accepts (2^53 - 1).
final BigInt _maxJsonSafe = BigInt.two.pow(53) - BigInt.one;

/// Largest nonce a Dart `int` holds exactly (2^63 - 1).
final BigInt _maxNonce = BigInt.two.pow(63) - BigInt.one;

/// Builds the exact `POST /api/wallet/send` body the backend's
/// `parseSignedTransfer` (backend `wallet-transfer-contract.js`) accepts.
///
/// [amountBaseUnits] and [nonce] are decimal integer strings. The amount is
/// signed and sent as the same integer base-unit string, and [from] and [to]
/// are signed and sent as the same strings. No floating point is involved.
Future<Map<String, String>> buildSignedTransferBody({
  required Ed25519TransferSigner signer,
  required TransferSigningDomain domain,
  required String from,
  required String to,
  required String amountBaseUnits,
  required String nonce,
}) async {
  if (!_positiveInteger.hasMatch(amountBaseUnits) ||
      BigInt.parse(amountBaseUnits) > _maxJsonSafe) {
    throw ArgumentError(
      'amountBaseUnits must be a positive integer string of at most 2^53-1',
    );
  }
  if (!_unsignedInteger.hasMatch(nonce) || BigInt.parse(nonce) > _maxNonce) {
    throw ArgumentError('nonce must be an unsigned integer string');
  }

  final message = transparentTransferAuthorizationMessage(
    chainId: domain.chainId,
    networkId: domain.networkId,
    from: from,
    to: to,
    amountBaseUnits: int.parse(amountBaseUnits),
    nonce: int.parse(nonce),
  );
  final signature = await signer.sign(message);

  return <String, String>{
    'from': from,
    'to': to,
    'amount': amountBaseUnits,
    'nonce': BigInt.parse(nonce).toString(),
    'auth_pubkey': _hex(signer.publicKey),
    'auth_signature': _hex(signature),
  };
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
