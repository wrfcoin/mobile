import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'key_manager.dart' show KeyValueStorage, SecureKeyValueStorage;
import 'signed_transfer.dart';
import 'station_signing.dart';

// The per-phone COLLECT KEY (design 2026-09-29-per-phone-station-registration
// §11, owner ruling). A second ed25519 key, generated on the device and held in
// Keystore-backed secure storage WITHOUT any biometric / user-auth gate, so the
// Workmanager isolate can sign commit authorizations while the app is closed.
// It has no spending power: the wallet key authorised it once, at registration
// (preimage A v2), and the backend refuses any commit whose `auth_pubkey` is
// not the registered collect key.
//
// The only thing this key can do is sign a commit authorization for this
// wallet's own station. It exposes no raw signer, no seed and no arbitrary
// message signing, so no wallet / send path can be handed it.

/// Capability for the Emergency Wipe UI: no key loading, generation or signing.
abstract interface class CollectKeyWiper {
  Future<void> wipe();
}

final collectKeyWiperProvider = Provider<CollectKeyWiper>(
  (ref) => _CollectKeyWiper(CollectKeyStore()),
);

class _CollectKeyWiper implements CollectKeyWiper {
  _CollectKeyWiper(this._store);
  final CollectKeyStore _store;
  @override
  Future<void> wipe() => _store.wipe();
}

const _seedKey = 'collect_key_seed';
const _ownerKey = 'collect_key_owner';

String _hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// What signs a commit authorization: the phone's collect key. The wallet
/// session deliberately does not implement this.
abstract class CommitSigner {
  String get stationId;

  /// Lower-case hex of the 32-byte public key sent as `auth_pubkey`.
  String get publicKeyHex;

  Future<SignedStationMessage> signCommitAuthorization({
    required String commitId,
  });
}

@immutable
class CollectKey implements CommitSigner {
  const CollectKey._(this._signer, this.ownerAddress, this.stationId);

  final Ed25519TransferSigner _signer;

  /// The wallet this key was authorised by.
  final String ownerAddress;

  @override
  final String stationId;

  @override
  String get publicKeyHex => _hexOf(_signer.publicKey);

  @override
  Future<SignedStationMessage> signCommitAuthorization({
    required String commitId,
  }) async {
    final domain = TransferSigningDomain.configured;
    final message = commitAuthorizationMessage(
      chainId: domain.chainId,
      networkId: domain.networkId,
      stationId: stationId,
      commitId: commitId,
      contributionType: collectContributionType,
    );
    final signature = await _signer.sign(message);
    return SignedStationMessage(
      message: message,
      signatureHex: _hexOf(signature),
      publicKeyHex: publicKeyHex,
    );
  }

  /// Public data only; never any key material.
  @override
  String toString() => 'CollectKey(station: $stationId)';
}

/// Generates, stores and loads the collect key. Reads never prompt.
class CollectKeyStore {
  /// [storage] defaults to a dedicated Keystore-backed namespace with no
  /// user-authentication requirement, separate from the wallet store so [wipe]
  /// can finish before wallet erasure.
  /// A stale key for another wallet is ignored: it is bound to its
  /// [CollectKey.ownerAddress].
  CollectKeyStore({KeyValueStorage? storage, Random? random})
    : _storage = storage ?? const SecureKeyValueStorage.collectKey(),
      _random = random ?? Random.secure();

  final KeyValueStorage _storage;
  final Random _random;

  /// Erases the dedicated collect-key namespace. Errors propagate so callers
  /// cannot erase the wallet while silently leaving its collect key behind.
  Future<void> wipe() => _storage.deleteAll();

  /// The stored key for [ownerAddress], or null when there is none (first
  /// run, reinstall, restore onto a new device) or it is unusable.
  Future<CollectKey?> load(String ownerAddress) async {
    final owner = ownerAddress.trim().toLowerCase();
    try {
      final storedOwner = await _storage.read(key: _ownerKey);
      final seed = await _storage.read(key: _seedKey);
      if (storedOwner != owner || seed == null || seed.isEmpty) return null;
      return await _build(seed, owner);
    } on ArgumentError {
      return null;
    } catch (_) {
      // An unreadable store is treated as "no key": the next foreground run
      // registers a fresh one rather than looping on a broken store.
      return null;
    }
  }

  /// Generates a fresh key for [ownerAddress] and replaces any stored one.
  Future<CollectKey> createFresh(String ownerAddress) async {
    final owner = ownerAddress.trim().toLowerCase();
    final seed = _hexOf(
      Uint8List.fromList(List<int>.generate(32, (_) => _random.nextInt(256))),
    );
    final key = await _build(seed, owner);
    await _storage.write(key: _seedKey, value: seed);
    await _storage.write(key: _ownerKey, value: owner);
    return key;
  }

  /// The stored key, or a fresh one when none exists. Generated once and
  /// reused on every later call.
  Future<CollectKey> loadOrCreate(String ownerAddress) async =>
      await load(ownerAddress) ?? await createFresh(ownerAddress);

  Future<CollectKey> _build(String seedHex, String owner) async {
    final signer = await Ed25519TransferSigner.fromSeedHex(seedHex);
    return CollectKey._(signer, owner, deriveMobileStationId(owner));
  }
}
