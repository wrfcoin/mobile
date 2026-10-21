import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/widgets.dart';
import 'package:pointycastle/digests/sha3.dart';

import 'key_manager.dart';
import 'signed_transfer.dart';

// Per-phone station identity and the three preimages a phone signs
// (design 2026-09-29-per-phone-station-registration-design.md §2, §3.2, §4).
// Every builder is a pure byte function pinned by golden vectors in
// test/services/crypto/station_signing_test.dart.

const _stationIdDomain = 'wrfcoin_mobile_station_v1';
// v2 (design §11): adds collect_pubkey; the tag bump means a v1 signature can
// never verify as v2. Byte-identical to backend `MOBILE_STATION_REG_DOMAIN`.
const _registrationDomain = 'wrfcoin_mobile_station_reg_v2';
const _ownershipDomain = 'wrfcoin_station_ownership_v1';
const _commitAuthDomain = 'wrfcoin_commit_auth_v2';

// Owner-action domains (core4 #3433 station_owner.rs / transaction.rs; spec
// r23/station-owner-actions-spec.md §2, PROVISIONAL until #3433 merges).
const _ownerTransferDomain = 'wrfcoin_station_owner_transfer_v1';
const _ownerTransferAcceptDomain = 'wrfcoin_station_owner_transfer_accept_v1';
const _ownerActionDomain = 'wrfcoin_station_owner_action_v1';
const _ownerRecoveryAcceptDomain = 'wrfcoin_station_owner_recovery_accept_v1';
const _ownerRecoveryCancelDomain = 'wrfcoin_station_owner_recovery_cancel_v1';

/// Prefix of every station id minted for a phone (reserved server-side).
const mobileStationIdPrefix = 'mob-';

/// v1 has one station per wallet; the slot byte is reserved (design §2.1).
const mobileStationSlot = 0;

/// core4 contribution type the Collect flow commits.
const collectContributionType = 'contribution';

final RegExp _chainAddress = RegExp(r'^0x[0-9a-f]{40}$');

Uint8List _u32le(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

Uint8List _i32le(int v) {
  if (v < -0x80000000 || v > 0x7fffffff) {
    throw ArgumentError('value does not fit in i32: $v');
  }
  return (ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List();
}

Uint8List _u64le(int v) {
  if (v < 0) throw ArgumentError('value must be unsigned: $v');
  return (ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List();
}

/// `lv(x)` = u32le(utf8 byte length) || utf8 bytes (core4 `push_chain_domain`).
List<int> _lv(String value) {
  final bytes = utf8.encode(value);
  return <int>[..._u32le(bytes.length), ...bytes];
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// `mob-` + hex(SHA-256("wrfcoin_mobile_station_v1" || 0x00 || address20 ||
/// slot_u8))[0..32]; byte-identical to backend `deriveMobileStationId`.
String deriveMobileStationId(
  String walletAddress, {
  int slot = mobileStationSlot,
}) {
  final normalized = walletAddress.trim().toLowerCase();
  if (!_chainAddress.hasMatch(normalized)) {
    throw ArgumentError(
      'wallet address must be a 0x-prefixed 20-byte hex chain address',
    );
  }
  final address20 = <int>[
    for (var i = 2; i < normalized.length; i += 2)
      int.parse(normalized.substring(i, i + 2), radix: 16),
  ];
  final digest = crypto.sha256.convert(<int>[
    ...utf8.encode(_stationIdDomain),
    0x00,
    ...address20,
    slot & 0xff,
  ]);
  return '$mobileStationIdPrefix${digest.toString().substring(0, 32)}';
}

/// Chain address of an ed25519 key: first 20 bytes of SHA3-256(pubkey).
String chainAddressFromEd25519PublicKey(Uint8List publicKey) {
  if (publicKey.length != 32) {
    throw ArgumentError('Ed25519 public key must be 32 bytes');
  }
  return '0x${_hex(SHA3Digest(256).process(publicKey).take(20).toList())}';
}

/// Preimage B: core4 `station_ownership_message_with_domain`.
Uint8List stationOwnershipMessage({
  required String chainId,
  required String networkId,
  required String stationId,
  required String ownerAddress,
}) => Uint8List.fromList(<int>[
  ...utf8.encode(_ownershipDomain),
  ..._lv(chainId),
  ..._lv(networkId),
  ..._lv(stationId),
  ..._lv(ownerAddress),
]);

/// Preimage A arguments (backend registration proof).
@immutable
class MobileStationRegistrationArgs {
  const MobileStationRegistrationArgs({
    required this.chainId,
    required this.networkId,
    required this.stationId,
    required this.ownerAddress,
    required this.collectPubkey,
    required this.latE1,
    required this.lonE1,
    required this.nonce,
    required this.expiresAt,
  });

  final String chainId;
  final String networkId;
  final String stationId;
  final String ownerAddress;

  /// The phone's collect key: 32-byte ed25519 public key, 64 lower-case hex.
  final String collectPubkey;

  /// Registered 0.1 degree cell, integer tenths of a degree.
  final int latE1;
  final int lonE1;
  final String nonce;

  /// Unix seconds.
  final int expiresAt;

  MobileStationRegistrationArgs copyWith({
    String? chainId,
    String? networkId,
    String? stationId,
    String? ownerAddress,
    String? collectPubkey,
    int? latE1,
    int? lonE1,
    String? nonce,
    int? expiresAt,
  }) => MobileStationRegistrationArgs(
    chainId: chainId ?? this.chainId,
    networkId: networkId ?? this.networkId,
    stationId: stationId ?? this.stationId,
    ownerAddress: ownerAddress ?? this.ownerAddress,
    collectPubkey: collectPubkey ?? this.collectPubkey,
    latE1: latE1 ?? this.latE1,
    lonE1: lonE1 ?? this.lonE1,
    nonce: nonce ?? this.nonce,
    expiresAt: expiresAt ?? this.expiresAt,
  );

  /// "wrfcoin_mobile_station_reg_v2" || lv(chain) || lv(network) ||
  /// lv(station) || lv(owner) || lv(collect_pubkey_hex) || i32le(lat_e1) ||
  /// i32le(lon_e1) || lv(nonce) || u64le(expires_at)
  Uint8List message() => mobileStationRegistrationMessage(
    chainId: chainId,
    networkId: networkId,
    stationId: stationId,
    ownerAddress: ownerAddress,
    collectPubkey: collectPubkey,
    latE1: latE1,
    lonE1: lonE1,
    nonce: nonce,
    expiresAt: expiresAt,
  );
}

Uint8List mobileStationRegistrationMessage({
  required String chainId,
  required String networkId,
  required String stationId,
  required String ownerAddress,
  required String collectPubkey,
  required int latE1,
  required int lonE1,
  required String nonce,
  required int expiresAt,
}) {
  // Lower-case hex, length-prefixed as UTF-8 text like `owner` (backend folds
  // case the same way before hashing it into the preimage).
  final collect = collectPubkey.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(collect)) {
    throw ArgumentError('collect_pubkey must be 32 bytes of hex');
  }
  return Uint8List.fromList(<int>[
    ...utf8.encode(_registrationDomain),
    ..._lv(chainId),
    ..._lv(networkId),
    ..._lv(stationId),
    ..._lv(ownerAddress),
    ..._lv(collect),
    ..._i32le(latE1),
    ..._i32le(lonE1),
    ..._lv(nonce),
    ..._u64le(expiresAt),
  ]);
}

/// core4 `commit_authorization_message_with_domain` (`wrfcoin_commit_auth_v2`).
Uint8List commitAuthorizationMessage({
  required String chainId,
  required String networkId,
  required String stationId,
  required String commitId,
  required String contributionType,
}) => Uint8List.fromList(<int>[
  ...utf8.encode(_commitAuthDomain),
  ..._lv(chainId),
  ..._lv(networkId),
  ..._lv(stationId),
  ..._lv(commitId),
  ..._lv(contributionType),
]);

// ── Owner actions (core4 #3433) ───────────────────────────────────────────
// Strings are signed EXACTLY as written (no case or prefix folding): the
// signature binds whichever spelling goes into the JSON payload.

void _checkStationId(String id) {
  if (id.isEmpty || RegExp(r'\s').hasMatch(id)) {
    throw ArgumentError('station_id must be non-empty with no whitespace');
  }
}

/// 20 raw bytes as lower-case hex after stripping one `0x` or `wrf` prefix
/// (core4 `same_station_owner`); null when not a 20-byte hex address.
String? _rawOwner(String address) {
  var a = address.trim().toLowerCase();
  if (a.startsWith('0x')) {
    a = a.substring(2);
  } else if (a.startsWith('wrf')) {
    a = a.substring(3);
  }
  return RegExp(r'^[0-9a-f]{40}$').hasMatch(a) ? a : null;
}

bool _sameOwner(String a, String b) {
  final ra = _rawOwner(a);
  final rb = _rawOwner(b);
  return ra != null && ra == rb;
}

/// Body shared by transfer (2.1) and transfer-accept (2.2): the new owner
/// countersigns the SAME fields under a different tag.
@immutable
class StationTransferBody {
  const StationTransferBody({
    required this.chainId,
    required this.networkId,
    required this.stationId,
    required this.fromOwnerAddress,
    required this.toOwnerAddress,
    required this.toOwnerPubkey,
    required this.transferNonce,
    required this.expiresAtHeight,
  });

  final String chainId;
  final String networkId;
  final String stationId;
  final String fromOwnerAddress;
  final String toOwnerAddress;

  /// 64 lower-case hex characters (ed25519), signed as text.
  final String toOwnerPubkey;
  final int transferNonce;
  final int expiresAtHeight;

  void _validate() {
    _checkStationId(stationId);
    if (_sameOwner(fromOwnerAddress, toOwnerAddress)) {
      throw ArgumentError('new owner must differ from the current owner');
    }
  }

  List<int> _body() {
    _validate();
    return <int>[
      ..._lv(chainId),
      ..._lv(networkId),
      ..._lv(stationId),
      ..._lv(fromOwnerAddress),
      ..._lv(toOwnerAddress),
      ..._lv(toOwnerPubkey),
      ..._u64le(transferNonce),
      ..._u64le(expiresAtHeight),
    ];
  }
}

/// Body shared by recovery filing and recovery accept (2.4, 2.5).
@immutable
class StationRecoveryBody {
  const StationRecoveryBody({
    required this.chainId,
    required this.networkId,
    required this.stationId,
    required this.fromOwnerAddress,
    required this.toOwnerAddress,
    required this.toOwnerPubkey,
    required this.recoveryNonce,
  });

  final String chainId;
  final String networkId;
  final String stationId;
  final String fromOwnerAddress;
  final String toOwnerAddress;
  final String toOwnerPubkey;
  final int recoveryNonce;

  List<int> _body() {
    _checkStationId(stationId);
    if (_sameOwner(fromOwnerAddress, toOwnerAddress)) {
      throw ArgumentError('new owner must differ from the current owner');
    }
    return <int>[
      ..._lv(chainId),
      ..._lv(networkId),
      ..._lv(stationId),
      ..._lv(fromOwnerAddress),
      ..._lv(toOwnerAddress),
      ..._lv(toOwnerPubkey),
      ..._u64le(recoveryNonce),
    ];
  }
}

/// Owner action discriminants are frozen on chain (TX:940-950).
enum StationOwnerAction {
  reportStolen(1, 'report_stolen'),
  unfreeze(2, 'unfreeze'),
  deactivate(3, 'deactivate'),
  reactivate(4, 'reactivate');

  const StationOwnerAction(this.discriminant, this.wireName);
  final int discriminant;

  /// Only actions with a published core4 golden may be signed by the app.
  /// All four now have one (report_stolen in #3433's fixture; unfreeze,
  /// deactivate, reactivate in core4 theft-lane commit 8457a09a2, PROVISIONAL
  /// until pushed). A future action without a golden must return false here.
  bool get shippable => true;

  /// JSON `action` value (snake_case).
  final String wireName;
}

/// 2.1: current owner signs. `TAG || chain || str(station) || str(from) ||
/// str(to) || str(to_pubkey) || u64le(nonce) || u64le(expires_at_height)`.
Uint8List stationOwnerTransferMessage(StationTransferBody b) =>
    Uint8List.fromList(<int>[
      ...utf8.encode(_ownerTransferDomain),
      ...b._body(),
    ]);

/// 2.2: new owner countersigns the same body under the accept tag.
Uint8List stationOwnerTransferAcceptMessage(StationTransferBody b) =>
    Uint8List.fromList(<int>[
      ...utf8.encode(_ownerTransferAcceptDomain),
      ...b._body(),
    ]);

/// 2.5: new owner accepts a recovery filing.
Uint8List stationOwnerRecoveryAcceptMessage(StationRecoveryBody b) =>
    Uint8List.fromList(<int>[
      ...utf8.encode(_ownerRecoveryAcceptDomain),
      ...b._body(),
    ]);

/// 2.6: current owner cancels a pending recovery (no expiry).
Uint8List stationOwnerRecoveryCancelMessage({
  required String chainId,
  required String networkId,
  required String stationId,
  required String ownerAddress,
  required int recoveryNonce,
}) {
  _checkStationId(stationId);
  return Uint8List.fromList(<int>[
    ...utf8.encode(_ownerRecoveryCancelDomain),
    ..._lv(chainId),
    ..._lv(networkId),
    ..._lv(stationId),
    ..._lv(ownerAddress),
    ..._u64le(recoveryNonce),
  ]);
}

/// 2.3: `TAG || chain || str(station) || str(owner) || u8(discriminant) ||
/// u64le(nonce) || u64le(expires_at_height)`.
Uint8List stationOwnerActionMessage({
  required String chainId,
  required String networkId,
  required String stationId,
  required String ownerAddress,
  required StationOwnerAction action,
  required int actionNonce,
  required int expiresAtHeight,
}) {
  _checkStationId(stationId);
  return Uint8List.fromList(<int>[
    ...utf8.encode(_ownerActionDomain),
    ..._lv(chainId),
    ..._lv(networkId),
    ..._lv(stationId),
    ..._lv(ownerAddress),
    action.discriminant,
    ..._u64le(actionNonce),
    ..._u64le(expiresAtHeight),
  ]);
}

/// A sender's transfer offer: the fixed body plus the sender's signature.
/// The body is what travels to the new owner (QR in slice B).
@immutable
class StationTransferOffer {
  const StationTransferOffer({required this.body, required this.signed});
  final StationTransferBody body;
  final SignedStationMessage signed;
}

String _addressOfPubkeyHex(String pubHex) => chainAddressFromEd25519PublicKey(
  Uint8List.fromList(<int>[
    for (var i = 0; i < pubHex.length; i += 2)
      int.parse(pubHex.substring(i, i + 2), radix: 16),
  ]),
);

/// A signed preimage. Holds no key material.
@immutable
class SignedStationMessage {
  const SignedStationMessage({
    required this.message,
    required this.signatureHex,
    required this.publicKeyHex,
  });

  final Uint8List message;
  final String signatureHex;
  final String publicKeyHex;
}

/// Signing needs the biometric-gated key, which only the foreground may read.
class StationSigningForegroundRequired implements Exception {
  const StationSigningForegroundRequired();
  @override
  String toString() =>
      'StationSigningForegroundRequired: station signing is foreground-only';
}

/// The wallet cannot sign station messages (legacy scheme, unusable or
/// inconsistent key). Carries a reason, never key material.
class StationSigningUnavailable implements Exception {
  const StationSigningUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'StationSigningUnavailable: $reason';
}

bool _defaultIsForeground() {
  try {
    return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  } catch (_) {
    // No binding (Workmanager isolate): definitely not the foreground UI.
    return false;
  }
}

/// Signs preimages A v2 and B with the wallet ed25519 key. Registration is the
/// wallet's only station duty: commit authorizations are signed by the phone's
/// collect key (`collect_key_store.dart`), never by the wallet (design §11).
///
/// [openSession] performs the one biometric-gated key read; the returned
/// session holds the signer in memory until [StationSigningSession.close].
/// Preimages are always built locally from [domain] (never server bytes).
class StationSigningService {
  StationSigningService({
    required this._keyManager,
    this._domain = TransferSigningDomain.configured,
    bool Function()? isForeground,
  }) : _isForeground = isForeground ?? _defaultIsForeground;

  final KeyManager _keyManager;
  final TransferSigningDomain _domain;
  final bool Function() _isForeground;

  /// Returns null when biometric authentication is refused.
  /// Throws [StationSigningForegroundRequired] outside the foreground and
  /// [StationSigningUnavailable] when the wallet cannot sign.
  Future<StationSigningSession?> openSession() async {
    if (!_isForeground()) throw const StationSigningForegroundRequired();
    if (!await _keyManager.canSignTransactions()) {
      throw const StationSigningUnavailable(
        'wallet is not a canonical ed25519 wallet',
      );
    }
    final storedAddress = (await _keyManager.getAddress())
        ?.trim()
        .toLowerCase();
    if (storedAddress == null || !_chainAddress.hasMatch(storedAddress)) {
      throw const StationSigningUnavailable('wallet has no chain address');
    }
    final seed = await _keyManager.getPrivateKey();
    if (seed == null || seed.isEmpty) return null;
    final Ed25519TransferSigner signer;
    try {
      signer = await Ed25519TransferSigner.fromSeedHex(seed);
    } on ArgumentError {
      throw const StationSigningUnavailable(
        'wallet key is not an ed25519 seed',
      );
    }
    if (chainAddressFromEd25519PublicKey(signer.publicKey) != storedAddress) {
      throw const StationSigningUnavailable(
        'wallet key does not derive to the stored address',
      );
    }
    return StationSigningSession._(signer, storedAddress, _domain);
  }
}

class StationSigningSession {
  StationSigningSession._(this._signer, this.ownerAddress, this._domain)
    : stationId = deriveMobileStationId(ownerAddress);

  Ed25519TransferSigner? _signer;
  final TransferSigningDomain _domain;

  /// Lower-case `0x` chain address of the signing wallet.
  final String ownerAddress;

  /// Chain identity this session signs under.
  String get chainId => _domain.chainId;
  String get networkId => _domain.networkId;

  /// This wallet's derived station id (slot 0).
  final String stationId;

  String get publicKeyHex => _hex(_live.publicKey);

  Ed25519TransferSigner get _live {
    final signer = _signer;
    if (signer == null) throw StateError('station signing session is closed');
    return signer;
  }

  Future<SignedStationMessage> _sign(Uint8List message) async {
    final signer = _live;
    final signature = await signer.sign(message);
    return SignedStationMessage(
      message: message,
      signatureHex: _hex(signature),
      publicKeyHex: _hex(signer.publicKey),
    );
  }

  /// Preimage B for this wallet's own station.
  Future<SignedStationMessage> signOwnership() =>
      signOwnershipFor(stationId: stationId);

  /// Preimage B for an explicit id (test vectors; production uses [signOwnership]).
  Future<SignedStationMessage> signOwnershipFor({required String stationId}) =>
      _sign(
        stationOwnershipMessage(
          chainId: _domain.chainId,
          networkId: _domain.networkId,
          stationId: stationId,
          ownerAddress: ownerAddress,
        ),
      );

  /// Preimage A for this wallet's own station and the server-issued challenge.
  Future<SignedStationMessage> signRegistration({
    required String collectPubkey,
    required int latE1,
    required int lonE1,
    required String nonce,
    required int expiresAt,
  }) => _sign(
    mobileStationRegistrationMessage(
      chainId: _domain.chainId,
      networkId: _domain.networkId,
      stationId: stationId,
      ownerAddress: ownerAddress,
      collectPubkey: collectPubkey,
      latE1: latE1,
      lonE1: lonE1,
      nonce: nonce,
      expiresAt: expiresAt,
    ),
  );

  /// 2.3. Only `report_stolen` has a core4 golden today; the other three
  /// discriminants stay unsupported until theft-lane adds their goldens.
  Future<SignedStationMessage> signOwnerAction({
    required StationOwnerAction action,
    required int actionNonce,
    required int expiresAtHeight,
  }) async {
    if (!action.shippable) {
      throw UnsupportedError(
        '${action.wireName} is not shippable until core4 publishes its golden',
      );
    }
    return _sign(
      stationOwnerActionMessage(
        chainId: _domain.chainId,
        networkId: _domain.networkId,
        stationId: stationId,
        ownerAddress: ownerAddress,
        action: action,
        actionNonce: actionNonce,
        expiresAtHeight: expiresAtHeight,
      ),
    );
  }

  /// 2.1: this wallet is the current owner of its own station and signs the
  /// fixed body. [toOwnerPubkey] must derive to [toOwnerAddress].
  Future<StationTransferOffer> signTransferAsSender({
    required String toOwnerAddress,
    required String toOwnerPubkey,
    required int transferNonce,
    required int expiresAtHeight,
  }) async {
    final pub = toOwnerPubkey.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pub) ||
        !_sameOwner(toOwnerAddress, _addressOfPubkeyHex(pub))) {
      throw const StationSigningUnavailable(
        'new owner key does not derive to the new owner address',
      );
    }
    final body = StationTransferBody(
      chainId: _domain.chainId,
      networkId: _domain.networkId,
      stationId: stationId,
      fromOwnerAddress: ownerAddress,
      toOwnerAddress: toOwnerAddress,
      toOwnerPubkey: pub,
      transferNonce: transferNonce,
      expiresAtHeight: expiresAtHeight,
    );
    return StationTransferOffer(
      body: body,
      signed: await _sign(stationOwnerTransferMessage(body)),
    );
  }

  /// 2.2: the new owner countersigns the sender's body after checking that it
  /// names THIS wallet, this key and this chain.
  Future<SignedStationMessage> countersignTransferAccept(
    StationTransferBody body,
  ) async {
    _requireNamesMe(
      chainId: body.chainId,
      networkId: body.networkId,
      toAddress: body.toOwnerAddress,
      toPubkey: body.toOwnerPubkey,
    );
    return _sign(stationOwnerTransferAcceptMessage(body));
  }

  /// 2.5: the new owner accepts a recovery filing naming this wallet.
  Future<SignedStationMessage> countersignRecoveryAccept(
    StationRecoveryBody body,
  ) async {
    _requireNamesMe(
      chainId: body.chainId,
      networkId: body.networkId,
      toAddress: body.toOwnerAddress,
      toPubkey: body.toOwnerPubkey,
    );
    return _sign(stationOwnerRecoveryAcceptMessage(body));
  }

  /// 2.6: the current owner cancels a pending recovery.
  Future<SignedStationMessage> signRecoveryCancel({
    required int recoveryNonce,
  }) => _sign(
    stationOwnerRecoveryCancelMessage(
      chainId: _domain.chainId,
      networkId: _domain.networkId,
      stationId: stationId,
      ownerAddress: ownerAddress,
      recoveryNonce: recoveryNonce,
    ),
  );

  void _requireNamesMe({
    required String chainId,
    required String networkId,
    required String toAddress,
    required String toPubkey,
  }) {
    if (chainId != _domain.chainId || networkId != _domain.networkId) {
      throw const StationSigningUnavailable(
        'request is for a different chain identity',
      );
    }
    if (!_sameOwner(toAddress, ownerAddress) ||
        toPubkey.trim().toLowerCase() != publicKeyHex) {
      throw const StationSigningUnavailable(
        'request does not name this wallet as the new owner',
      );
    }
  }

  /// Drops the signer. Further signing throws [StateError].
  void close() => _signer = null;

  @override
  String toString() => 'StationSigningSession(station: $stationId)';
}

/// Same owner by 20 raw bytes after stripping one `0x`/`wrf` prefix (core4
/// `same_station_owner`). False when either side is not a 20-byte address.
bool sameStationOwner(String a, String b) => _sameOwner(a, b);

/// Chain address of an ed25519 public key given as 64 hex characters.
String addressOfEd25519PublicKeyHex(String pubHex) =>
    _addressOfPubkeyHex(pubHex.trim().toLowerCase());
