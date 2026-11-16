import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'key_manager.dart';
import 'signed_transfer.dart';
import 'station_signing.dart' show chainAddressFromEd25519PublicKey;

/// Advisory governance signing (core4 `governance::advisory`, chain 888).
///
/// Byte for byte the same as core4 `advisory_action_message` and the
/// website's `advisoryActionMessage` (frontend
/// `src/services/walletCrypto/advisoryGovernance.ts`): every component framed
/// by a u64-LE length (tag, chain id, network id, 20 account bytes, encoded
/// action, 8 nonce bytes LE). Pinned by the vectors core4 generated for the
/// website (`test/services/crypto/advisory_governance_vectors.json`).
///
/// The app signs with its OWN wallet key (the biometric-gated ed25519 seed in
/// [KeyManager]); the recovery phrase is never read.
const String advisoryActionDomainTag = 'wrfcoin.advisory_governance_action.v1';

/// core4 MAX_TITLE_BYTES / MAX_SUMMARY_BYTES (UTF-8 bytes).
const int advisoryMaxTitleBytes = 160;
const int advisoryMaxSummaryBytes = 1024;

/// 1 WRF in base units: the proposal deposit (core4 ADVISORY_DEPOSIT). The
/// advisory transaction itself pays no fee (the relay builds it with fee 0).
final BigInt advisoryDepositUnits = BigInt.from(100000000);

enum AdvisoryTextField { title, summary }

/// Text rules as core4 `validate_text` and the website's
/// `advisoryTextProblem` (bytes, blank, one-line title, C0/C1 controls and
/// bidi characters). A person-readable problem, or null. Same wording as
/// the website.
String? advisoryTextProblem(AdvisoryTextField field, String text) {
  final isTitle = field == AdvisoryTextField.title;
  final name = isTitle ? 'The title' : 'The summary';
  if (text.trim().isEmpty) return '$name is empty.';
  final max = isTitle ? advisoryMaxTitleBytes : advisoryMaxSummaryBytes;
  final bytes = utf8.encode(text).length;
  if (bytes > max) return '$name is $bytes bytes; the limit is $max.';
  for (final cp in text.runes) {
    if (cp == 0x0a) {
      if (isTitle) return 'The title must be one line.';
      continue;
    }
    // A lone surrogate can't be encoded faithfully (the backend refuses it).
    if ((cp >= 0xd800 && cp <= 0xdfff) ||
        cp <= 0x1f ||
        (cp >= 0x7f && cp <= 0x9f) ||
        (cp >= 0x202a && cp <= 0x202e) ||
        (cp >= 0x2066 && cp <= 0x2069)) {
      final hex = cp.toRadixString(16).toUpperCase().padLeft(4, '0');
      return '$name has a character that is not allowed (U+$hex).';
    }
  }
  return null;
}

/// Largest nonce the relay's JSON carries exactly (2^53 - 1), as the website.
const int advisoryMaxNonce = 9007199254740991;

final RegExp _proposalId = RegExp(r'^adv-[0-9a-f]{16}$');
final RegExp _address = RegExp(r'^0x[0-9a-f]{40}$');

/// One signed action: a vote on a proposal, or a new proposal.
sealed class AdvisoryAction {
  const AdvisoryAction();

  /// core4 `encode_action_for_preimage`.
  List<int> encode();

  /// serde's externally tagged, snake_case JSON (core4 `AdvisoryAction`).
  Map<String, dynamic> toJson();
}

class AdvisoryVote extends AdvisoryAction {
  const AdvisoryVote({required this.proposalId, required this.approve});

  final String proposalId;

  /// true = for, false = against.
  final bool approve;

  @override
  List<int> encode() => <int>[
    0x02,
    ..._framed(utf8.encode(proposalId)),
    approve ? 1 : 0,
  ];

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'vote': <String, dynamic>{'proposal_id': proposalId, 'approve': approve},
  };
}

class AdvisoryPropose extends AdvisoryAction {
  const AdvisoryPropose({required this.title, required this.summary});

  final String title;
  final String summary;

  @override
  List<int> encode() => <int>[
    0x01,
    ..._framed(utf8.encode(title)),
    ..._framed(utf8.encode(summary)),
  ];

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'propose': <String, dynamic>{'title': title, 'summary': summary},
  };
}

List<int> _u64le(int value) {
  final bytes = ByteData(8)..setUint64(0, value, Endian.little);
  return bytes.buffer.asUint8List();
}

/// core4 `push`: u64-LE length, then the bytes.
List<int> _framed(List<int> bytes) => <int>[..._u64le(bytes.length), ...bytes];

List<int> _addressBytes(String account) {
  final a = account.trim().toLowerCase();
  if (!_address.hasMatch(a)) {
    throw ArgumentError('account must be a 0x-prefixed 20-byte hex address');
  }
  return <int>[
    for (var i = 2; i < a.length; i += 2)
      int.parse(a.substring(i, i + 2), radix: 16),
  ];
}

void _checkNonce(int nonce) {
  if (nonce < 0 || nonce > advisoryMaxNonce) {
    throw ArgumentError('nonce out of range');
  }
}

/// core4 `advisory_action_message`: the exact bytes the wallet key signs.
Uint8List advisoryActionMessage({
  required String chainId,
  required String networkId,
  required String account,
  required AdvisoryAction action,
  required int nonce,
}) {
  _checkNonce(nonce);
  if (action is AdvisoryVote && !_proposalId.hasMatch(action.proposalId)) {
    throw ArgumentError('not an advisory proposal id');
  }
  return Uint8List.fromList(<int>[
    ..._framed(utf8.encode(advisoryActionDomainTag)),
    ..._framed(utf8.encode(chainId)),
    ..._framed(utf8.encode(networkId)),
    ..._framed(_addressBytes(account)),
    ..._framed(action.encode()),
    ..._framed(_u64le(nonce)),
  ]);
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The `SignedAdvisoryAction` JSON body the relay
/// (`POST /api/governance/advisory/actions`) takes, ed25519 form, in serde
/// member order: account (20-byte array), action, nonce, public_key,
/// signature. Same as the website's `signedEd25519Action`.
Future<Map<String, dynamic>> signedEd25519AdvisoryAction({
  required Ed25519TransferSigner signer,
  required String chainId,
  required String networkId,
  required String account,
  required AdvisoryAction action,
  required int nonce,
}) async {
  final owner = account.trim().toLowerCase();
  final message = advisoryActionMessage(
    chainId: chainId,
    networkId: networkId,
    account: owner,
    action: action,
    nonce: nonce,
  );
  final signature = await signer.sign(message);
  return <String, dynamic>{
    'account': _addressBytes(owner),
    'action': action.toJson(),
    'nonce': nonce,
    'public_key': _hex(signer.publicKey),
    'signature': _hex(signature),
  };
}

/// Why the app can't sign an advisory action. [message] is shown as is.
class AdvisorySigningUnavailable implements Exception {
  const AdvisorySigningUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The person cancelled (or failed) the device unlock. Nothing was sent.
class AdvisoryUnlockCancelled implements Exception {
  const AdvisoryUnlockCancelled();
  @override
  String toString() => 'Unlock cancelled. Nothing was sent.';
}

/// Which wallet can vote, read without unlocking anything.
class AdvisoryVoter {
  const AdvisoryVoter({required this.address, required this.canSign});

  /// Lowercase 0x address, or null when the app holds no wallet.
  final String? address;

  /// The wallet holds an ed25519 key (scheme `ed25519-slip10`). Older
  /// receive-only wallets can't sign advisory actions.
  final bool canSign;
}

/// Opens the biometric-gated wallet seed (the same [KeyManager.getPrivateKey]
/// gate a send uses), in the foreground, for one advisory action. Never reads
/// the mnemonic, the login key or the collect key.
class AdvisoryActionSigner {
  AdvisoryActionSigner({
    required KeyManager keyManager,
    TransferSigningDomain? domain,
    bool Function()? isForeground,
  }) : _keys = keyManager,
       _domain = domain ?? TransferSigningDomain.configured,
       _isForeground = isForeground ?? _foreground;

  final KeyManager _keys;
  final TransferSigningDomain _domain;
  final bool Function() _isForeground;

  static bool _foreground() {
    try {
      return WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
    } catch (_) {
      return false;
    }
  }

  /// The wallet that would vote. No unlock prompt.
  Future<AdvisoryVoter> voter() async {
    if (!await _keys.hasWallet()) {
      return const AdvisoryVoter(address: null, canSign: false);
    }
    final address = (await _keys.getAddress())?.trim().toLowerCase();
    return AdvisoryVoter(
      address: address,
      canSign:
          address != null &&
          _address.hasMatch(address) &&
          await _keys.canSignTransactions(),
    );
  }

  /// Unlocks the wallet key (one device prompt) and signs [action] at
  /// [nonce]. Throws [AdvisoryUnlockCancelled] if the unlock is refused,
  /// [AdvisorySigningUnavailable] if this wallet can't sign.
  Future<Map<String, dynamic>> sign(AdvisoryAction action, int nonce) async {
    if (_domain.chainId.isEmpty) {
      throw const AdvisorySigningUnavailable(
        'This build has no chain configured, so it cannot sign.',
      );
    }
    if (!_isForeground()) {
      throw const AdvisorySigningUnavailable('Open the app to sign your vote.');
    }
    final who = await voter();
    final address = who.address;
    if (address == null) {
      throw const AdvisorySigningUnavailable(
        'Create or import a wallet in the app first.',
      );
    }
    if (!who.canSign) {
      throw const AdvisorySigningUnavailable(
        "This wallet type can't vote yet.",
      );
    }
    final seed = await _keys.getPrivateKey();
    if (seed == null || seed.isEmpty) throw const AdvisoryUnlockCancelled();
    final Ed25519TransferSigner signer;
    try {
      signer = await Ed25519TransferSigner.fromSeedHex(seed);
    } on ArgumentError {
      throw const AdvisorySigningUnavailable('The wallet key is unavailable.');
    }
    if (chainAddressFromEd25519PublicKey(signer.publicKey) != address) {
      throw const AdvisorySigningUnavailable(
        'The wallet key does not match its address.',
      );
    }
    // The unlock prompt can background the app; refuse if it did.
    if (!_isForeground()) {
      throw const AdvisorySigningUnavailable('Open the app to sign your vote.');
    }
    return signedEd25519AdvisoryAction(
      signer: signer,
      chainId: _domain.chainId,
      networkId: _domain.networkId,
      account: address,
      action: action,
      nonce: nonce,
    );
  }
}
