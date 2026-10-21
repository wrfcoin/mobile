import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../../../../services/crypto/station_signing.dart';

// The two-party exchange text (QR or paste). It carries ONLY public values:
// addresses, public keys, the fixed body and the sender's signature. Decoding
// is strict and rejects any extra field, so key material can never ride along.

const _offerKind = 'station_transfer_offer_v1';
const _receiveKind = 'station_receive_code_v1';
final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _hex128 = RegExp(r'^[0-9a-f]{128}$');

/// Self-describing, versioned, checksummed text (what the QR shows and the
/// receiver pastes):  `WRFOWN1.<kind>.<base64url(json)>.<checksum8>`.
/// The checksum is the first 4 bytes of sha256 over everything before it, so a
/// truncated or mangled paste is refused before anything is read or signed.
const exchangePrefix = 'WRFOWN1';

String _checksum(String body) =>
    crypto.sha256.convert(utf8.encode(body)).toString().substring(0, 8);

/// Frames [json] as exchange text for [kind] (`offer` or `receive`).
@visibleForTesting
String packExchangeText(String kind, Object json) {
  final b64 = base64Url
      .encode(utf8.encode(jsonEncode(json)))
      .replaceAll('=', '');
  final body = '$exchangePrefix.$kind.$b64';
  return '$body.${_checksum(body)}';
}

Map<String, dynamic> _object(String text, String kind, Set<String> keys) {
  // Pasted text may be wrapped or padded with whitespace.
  final t = text.replaceAll(RegExp(r'\s+'), '');
  final parts = t.split('.');
  if (parts.length != 4 || parts[0] != exchangePrefix) {
    throw const FormatException('not an owner exchange code');
  }
  if (parts[1] != kind) throw const FormatException('wrong kind of code');
  final body = '${parts[0]}.${parts[1]}.${parts[2]}';
  if (parts[3] != _checksum(body)) {
    throw const FormatException('code is truncated or damaged');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[2]))),
    );
  } on FormatException {
    throw const FormatException('not a valid exchange code');
  }
  if (decoded is! Map) throw const FormatException('not an exchange object');
  final m = Map<String, dynamic>.from(decoded);
  if (m['v'] != 1) throw const FormatException('unsupported exchange version');
  if (m.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(m.keys.toSet()).isNotEmpty) {
    throw const FormatException('unexpected exchange fields');
  }
  return m;
}

String _s(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is String && v.isNotEmpty) return v;
  throw FormatException('bad field $k');
}

int _i(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is int && v >= 0) return v;
  throw FormatException('bad field $k');
}

String _hex(Map<String, dynamic> m, String k, RegExp re) {
  final v = _s(m, k);
  if (!re.hasMatch(v)) throw FormatException('bad field $k');
  return v;
}

/// What a prospective new owner shows the sender (public values only).
@immutable
class ReceiveCode {
  const ReceiveCode({required this.address, required this.pubkey});

  factory ReceiveCode.decode(String text) {
    final m = _object(text, 'receive', {'v', 'kind', 'address', 'pubkey'});
    if (m['kind'] != _receiveKind) throw const FormatException('wrong kind');
    final address = _s(m, 'address');
    final pubkey = _hex(m, 'pubkey', _hex64);
    if (!sameStationOwner(address, addressOfEd25519PublicKeyHex(pubkey))) {
      throw const FormatException('public key does not match the address');
    }
    return ReceiveCode(address: address, pubkey: pubkey);
  }

  final String address;
  final String pubkey;

  String encode() => packExchangeText('receive', <String, dynamic>{
    'v': 1,
    'kind': _receiveKind,
    'address': address,
    'pubkey': pubkey,
  });
}

/// The sender's signed transfer, travelling to the new owner.
@immutable
class TransferOffer {
  const TransferOffer({
    required this.body,
    required this.fromOwnerPubkey,
    required this.fromOwnerSignature,
  });

  factory TransferOffer.fromSigned(StationTransferOffer o) => TransferOffer(
    body: o.body,
    fromOwnerPubkey: o.signed.publicKeyHex,
    fromOwnerSignature: o.signed.signatureHex,
  );

  factory TransferOffer.decode(String text) {
    final m = _object(text, 'offer', {
      'v',
      'kind',
      'chain_id',
      'network_id',
      'station_id',
      'from_owner_address',
      'from_owner_pubkey',
      'to_owner_address',
      'to_owner_pubkey',
      'transfer_nonce',
      'expires_at_height',
      'from_owner_signature',
    });
    if (m['kind'] != _offerKind) throw const FormatException('wrong kind');
    return TransferOffer(
      body: StationTransferBody(
        chainId: _s(m, 'chain_id'),
        networkId: _s(m, 'network_id'),
        stationId: _s(m, 'station_id'),
        fromOwnerAddress: _s(m, 'from_owner_address'),
        toOwnerAddress: _s(m, 'to_owner_address'),
        toOwnerPubkey: _hex(m, 'to_owner_pubkey', _hex64),
        transferNonce: _i(m, 'transfer_nonce'),
        expiresAtHeight: _i(m, 'expires_at_height'),
      ),
      fromOwnerPubkey: _hex(m, 'from_owner_pubkey', _hex64),
      fromOwnerSignature: _hex(m, 'from_owner_signature', _hex128),
    );
  }

  final StationTransferBody body;
  final String fromOwnerPubkey;
  final String fromOwnerSignature;

  String encode() => packExchangeText('offer', <String, dynamic>{
    'v': 1,
    'kind': _offerKind,
    'chain_id': body.chainId,
    'network_id': body.networkId,
    'station_id': body.stationId,
    'from_owner_address': body.fromOwnerAddress,
    'from_owner_pubkey': fromOwnerPubkey,
    'to_owner_address': body.toOwnerAddress,
    'to_owner_pubkey': body.toOwnerPubkey,
    'transfer_nonce': body.transferNonce,
    'expires_at_height': body.expiresAtHeight,
    'from_owner_signature': fromOwnerSignature,
  });
}

/// The `tx.data` payload JSON for a transfer (spec §3). Unset signature
/// fields are omitted.
String transferPayloadJson(
  TransferOffer offer, {
  required String? toOwnerSignature,
}) => jsonEncode(<String, dynamic>{
  'tx_kind': 'station_owner_transfer_v1',
  'station_id': offer.body.stationId,
  'from_owner_address': offer.body.fromOwnerAddress,
  'from_owner_pubkey': offer.fromOwnerPubkey,
  'to_owner_address': offer.body.toOwnerAddress,
  'to_owner_pubkey': offer.body.toOwnerPubkey,
  'transfer_nonce': offer.body.transferNonce,
  'expires_at_height': offer.body.expiresAtHeight,
  'from_owner_signature': offer.fromOwnerSignature,
  'to_owner_signature': ?toOwnerSignature,
});

/// The `tx.data` payload JSON for an owner action (spec §3).
String ownerActionPayloadJson({
  required String stationId,
  required String ownerAddress,
  required String ownerPubkey,
  required StationOwnerAction action,
  required int actionNonce,
  required int expiresAtHeight,
  required String ownerSignature,
}) => jsonEncode(<String, dynamic>{
  'tx_kind': 'station_owner_action_v1',
  'station_id': stationId,
  'owner_address': ownerAddress,
  'owner_pubkey': ownerPubkey,
  'action': action.wireName,
  'action_nonce': actionNonce,
  'expires_at_height': expiresAtHeight,
  'owner_signature': ownerSignature,
});

const _recoveryRequestKind = 'station_recovery_request_v1';
const _recoveryAcceptKind = 'station_recovery_accept_v1';

Map<String, dynamic> _recoveryFields(StationRecoveryBody b) =>
    <String, dynamic>{
      'chain_id': b.chainId,
      'network_id': b.networkId,
      'station_id': b.stationId,
      'from_owner_address': b.fromOwnerAddress,
      'to_owner_address': b.toOwnerAddress,
      'to_owner_pubkey': b.toOwnerPubkey,
      'recovery_nonce': b.recoveryNonce,
    };

StationRecoveryBody _recoveryBody(Map<String, dynamic> m) =>
    StationRecoveryBody(
      chainId: _s(m, 'chain_id'),
      networkId: _s(m, 'network_id'),
      stationId: _s(m, 'station_id'),
      fromOwnerAddress: _s(m, 'from_owner_address'),
      toOwnerAddress: _s(m, 'to_owner_address'),
      toOwnerPubkey: _hex(m, 'to_owner_pubkey', _hex64),
      recoveryNonce: _i(m, 'recovery_nonce'),
    );

const _recoveryKeys = {
  'v',
  'kind',
  'chain_id',
  'network_id',
  'station_id',
  'from_owner_address',
  'to_owner_address',
  'to_owner_pubkey',
  'recovery_nonce',
};

/// The recovery body an operator prepares for the claimant to countersign.
/// Offline only: the claimant never submits it.
@immutable
class RecoveryRequest {
  const RecoveryRequest({required this.body});

  factory RecoveryRequest.decode(String text) {
    final m = _object(text, 'recovery', _recoveryKeys);
    if (m['kind'] != _recoveryRequestKind) {
      throw const FormatException('wrong kind');
    }
    return RecoveryRequest(body: _recoveryBody(m));
  }

  final StationRecoveryBody body;

  String encode() => packExchangeText('recovery', <String, dynamic>{
    'v': 1,
    'kind': _recoveryRequestKind,
    ..._recoveryFields(body),
  });
}

/// What the claimant hands BACK to the operator: the same body plus the
/// countersignature (`to_owner_signature`).
@immutable
class RecoveryAcceptText {
  const RecoveryAcceptText({
    required this.body,
    required this.toOwnerSignature,
  });

  factory RecoveryAcceptText.decode(String text) {
    final m = _object(text, 'recovery-accept', {
      ..._recoveryKeys,
      'to_owner_signature',
    });
    if (m['kind'] != _recoveryAcceptKind) {
      throw const FormatException('wrong kind');
    }
    return RecoveryAcceptText(
      body: _recoveryBody(m),
      toOwnerSignature: _hex(m, 'to_owner_signature', _hex128),
    );
  }

  final StationRecoveryBody body;
  final String toOwnerSignature;

  String encode() => packExchangeText('recovery-accept', <String, dynamic>{
    'v': 1,
    'kind': _recoveryAcceptKind,
    ..._recoveryFields(body),
    'to_owner_signature': toOwnerSignature,
  });
}

/// `tx.data` for a recovery cancel (spec §3).
String recoveryCancelPayloadJson({
  required String stationId,
  required String ownerAddress,
  required String ownerPubkey,
  required int recoveryNonce,
  required String ownerSignature,
}) => jsonEncode(<String, dynamic>{
  'tx_kind': 'station_owner_recovery_cancel_v1',
  'station_id': stationId,
  'owner_address': ownerAddress,
  'owner_pubkey': ownerPubkey,
  'recovery_nonce': recoveryNonce,
  'owner_signature': ownerSignature,
});

/// `tx.data` for a recovery execute: unsigned and permissionless.
String recoveryExecutePayloadJson({
  required String stationId,
  required int recoveryNonce,
}) => jsonEncode(<String, dynamic>{
  'tx_kind': 'station_owner_recovery_execute_v1',
  'station_id': stationId,
  'recovery_nonce': recoveryNonce,
});
