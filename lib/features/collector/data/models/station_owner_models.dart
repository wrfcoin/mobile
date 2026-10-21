import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

// Ownership read of the backend relay (backend#1459, spec rev e14b961): FLAT
// camelCase. Parsing is strict: a missing or mistyped key throws
// FormatException and is never defaulted into "not frozen / nothing pending".

int _int(Object? v, String name) {
  if (v is int && v >= 0) return v;
  throw FormatException('ownership: $name must be a non-negative integer', v);
}

bool _bool(Object? v, String name) {
  if (v is bool) return v;
  throw FormatException('ownership: $name must be a bool', v);
}

String _str(Object? v, String name) {
  if (v is String && v.isNotEmpty) return v;
  throw FormatException('ownership: $name must be a string', v);
}

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

String _commitment(Object? v, String name) {
  final s = _str(v, name);
  if (!_hex64.hasMatch(s)) {
    throw FormatException('ownership: bad $name', s);
  }
  return s;
}

/// 20 raw address bytes as lowercase hex: `0x...`, `wrf...` and `WRF...`
/// spellings (and bare hex) of the same bytes agree. Anything that is not
/// exactly 40 hex digits throws [ArgumentError].
String addressRawHex(String address) {
  var a = address.trim().toLowerCase();
  if (a.startsWith('0x')) {
    a = a.substring(2);
  } else if (a.startsWith('wrf')) {
    a = a.substring(3);
  }
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(a)) {
    throw ArgumentError('address must be exactly 40 hex digits (20 bytes)');
  }
  return a;
}

/// `sha256("wrfcoin-owner-commit-v1:" + stationId + ":" + lowercase hex of the
/// 20 RAW address bytes, no prefix)` as lowercase hex (backend#1459, format
/// v1). The station id is RAW. The backend shows the registered owner SHORT to
/// most viewers, so ownership is checked by commitment, never by the display
/// address.
String ownerCommitment(String stationId, String address) => crypto.sha256
    .convert(
      utf8.encode(
        'wrfcoin-owner-commit-v1:$stationId:${addressRawHex(address)}',
      ),
    )
    .toString();

@immutable
class PendingRecovery {
  const PendingRecovery({
    required this.fromOwnerAddress,
    required this.toOwnerAddress,
    required this.fromOwnerCommitment,
    required this.toOwnerCommitment,
    required this.recoveryNonce,
    required this.filedAtHeight,
    required this.executableAtHeight,
    required this.noticeBlocks,
  });

  factory PendingRecovery.fromJson(Map<String, dynamic> j) => PendingRecovery(
    fromOwnerAddress: _str(j['fromOwner'], 'fromOwner'),
    toOwnerAddress: _str(j['toOwner'], 'toOwner'),
    fromOwnerCommitment: _commitment(
      j['fromOwnerCommitment'],
      'fromOwnerCommitment',
    ),
    toOwnerCommitment: _commitment(j['toOwnerCommitment'], 'toOwnerCommitment'),
    recoveryNonce: _int(j['recoveryNonce'], 'recoveryNonce'),
    filedAtHeight: _int(j['filedAtHeight'], 'filedAtHeight'),
    executableAtHeight: _int(j['executableAtHeight'], 'executableAtHeight'),
    noticeBlocks: _int(j['noticeBlocks'], 'noticeBlocks'),
  );

  /// Display addresses: SHORT unless the viewer is the owner or an operator.
  final String fromOwnerAddress;
  final String toOwnerAddress;

  /// Commitments of the two parties: compare these, never the display forms.
  final String fromOwnerCommitment;
  final String toOwnerCommitment;
  final int recoveryNonce;
  final int filedAtHeight;
  final int executableAtHeight;
  final int noticeBlocks;
}

@immutable
class OwnerLedger {
  const OwnerLedger({
    required this.owner,
    required this.ownerCommitment,
    required this.isOwner,
    required this.ownerNonce,
    required this.frozenSinceHeight,
    required this.ownerDeactivated,
    required this.pendingRecovery,
    required this.rewardsSuspended,
    required this.consentActive,
    required this.actionsActive,
    required this.observedAtHeight,
    required this.settledHeight,
  });

  factory OwnerLedger.fromJson(Object? body) {
    if (body is! Map) {
      throw FormatException('ownership: not an object', body);
    }
    final j = Map<String, dynamic>.from(body);
    for (final key in const [
      'frozen',
      'pendingRecovery',
      'features',
      'ownerCommitment',
    ]) {
      if (!j.containsKey(key)) {
        throw FormatException('ownership: $key missing');
      }
    }
    final features = j['features'];
    if (features is! Map) {
      throw FormatException('ownership: features missing', features);
    }
    final commitment = _commitment(j['ownerCommitment'], 'ownerCommitment');
    final frozen = j['frozen'];
    final pending = j['pendingRecovery'];
    return OwnerLedger(
      owner: _str(j['owner'], 'owner'),
      ownerCommitment: commitment,
      isOwner: _bool(j['isOwner'], 'isOwner'),
      ownerNonce: _int(j['ownerNonce'], 'ownerNonce'),
      frozenSinceHeight: frozen == null
          ? null
          : frozen is Map
          ? _int(frozen['sinceHeight'], 'frozen.sinceHeight')
          : throw FormatException('ownership: bad frozen', frozen),
      ownerDeactivated: _bool(j['ownerDeactivated'], 'ownerDeactivated'),
      pendingRecovery: pending == null
          ? null
          : pending is Map
          ? PendingRecovery.fromJson(Map<String, dynamic>.from(pending))
          : throw FormatException('ownership: bad pendingRecovery', pending),
      rewardsSuspended: _bool(j['rewardsSuspended'], 'rewardsSuspended'),
      consentActive: _bool(
        features['stationOwnerConsent'],
        'stationOwnerConsent',
      ),
      actionsActive: _bool(
        features['stationOwnerActions'],
        'stationOwnerActions',
      ),
      observedAtHeight: _int(j['observedAtHeight'], 'observedAtHeight'),
      settledHeight: _int(j['settledHeight'], 'settledHeight'),
    );
  }

  /// Registered owner as DISPLAYED (short for most viewers). Never compare
  /// against it; use [ownerIs].
  final String owner;
  final String ownerCommitment;

  /// Whether the logged-in wallet is the owner (false when not logged in).
  final bool isOwner;

  /// The nonce the NEXT owner tx must carry.
  final int ownerNonce;
  final int? frozenSinceHeight;
  final bool ownerDeactivated;
  final PendingRecovery? pendingRecovery;
  final bool rewardsSuspended;
  final bool consentActive;
  final bool actionsActive;
  final int observedAtHeight;
  final int settledHeight;

  bool get frozen => frozenSinceHeight != null;

  /// Whether [fullAddress] is the registered owner of [stationId]: its
  /// commitment equals the ledger's. A short or malformed address never
  /// matches.
  bool ownerIs(String stationId, String fullAddress) {
    try {
      return commitmentFor(stationId, fullAddress) == ownerCommitment;
    } on ArgumentError {
      return false;
    }
  }
}

/// Same as [ownerCommitment]; a distinct name so [OwnerLedger], whose field is
/// also called `ownerCommitment`, can call it.
String commitmentFor(String stationId, String address) =>
    ownerCommitment(stationId, address);
