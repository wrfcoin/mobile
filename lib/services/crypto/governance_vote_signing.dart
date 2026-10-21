import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'key_manager.dart';
import 'signed_transfer.dart';
import 'station_signing.dart' show chainAddressFromEd25519PublicKey;

/// Raw v1 bytes selected by the owner for chain 777 and backend#1337.
/// V1 has no framing or chain/network binding. No caller supplies message bytes.
List<int> governanceVoteV1Message(String proposalId, bool approve) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(proposalId)) {
    throw const GovernanceSigningUnavailable('Invalid proposal identifier.');
  }
  return utf8.encode(
    'governance-vote-v1|$proposalId|${approve ? 'approve' : 'reject'}',
  );
}

class GovernanceSigningUnavailable implements Exception {
  const GovernanceSigningUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Opens only the biometric-gated wallet seed, in the foreground, for one vote.
/// The collect key and login-private-key entry are never read.
class GovernanceVoteSigner {
  GovernanceVoteSigner({
    required KeyManager keyManager,
    bool Function()? isForeground,
    this.version = configuredVersion,
  }) : _keys = keyManager,
       _isForeground = isForeground ?? _foreground;

  static const configuredVersion = int.fromEnvironment(
    'WRFCOIN_GOVERNANCE_SIGNING_VERSION',
    defaultValue: 1,
  );
  final int version;
  final KeyManager _keys;
  final bool Function() _isForeground;

  static bool _foreground() {
    try {
      return WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>?> signVote(String proposalId, bool approve) async {
    if (version != 1) {
      throw const GovernanceSigningUnavailable(
        'This build does not support the configured voting protocol.',
      );
    }
    final message = governanceVoteV1Message(proposalId, approve);
    if (!_isForeground()) {
      throw const GovernanceSigningUnavailable(
        'Open the app to sign your vote.',
      );
    }
    if (!await _keys.canSignTransactions()) {
      throw const GovernanceSigningUnavailable(
        'An ed25519 wallet is required to sign your vote.',
      );
    }
    final address = (await _keys.getAddress())?.trim().toLowerCase();
    if (address == null ||
        (await _keys.getLoginAddress())?.trim().toLowerCase() != address) {
      throw const GovernanceSigningUnavailable(
        'The signed-in wallet must match the voting wallet.',
      );
    }
    final seed = await _keys.getPrivateKey();
    if (seed == null || seed.isEmpty) return null;
    final Ed25519TransferSigner signer;
    try {
      signer = await Ed25519TransferSigner.fromSeedHex(seed);
    } on ArgumentError {
      throw const GovernanceSigningUnavailable(
        'The wallet key is unavailable.',
      );
    }
    if (chainAddressFromEd25519PublicKey(signer.publicKey) != address) {
      throw const GovernanceSigningUnavailable(
        'The wallet key does not match its address.',
      );
    }
    // Authentication can await platform UI. Refuse if the app lost foreground.
    if (!_isForeground()) {
      throw const GovernanceSigningUnavailable(
        'Open the app to sign your vote.',
      );
    }
    final signature = await signer.sign(message);
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return {
      'signer_public_key': hex(signer.publicKey),
      'signature': hex(signature),
    };
  }
}
