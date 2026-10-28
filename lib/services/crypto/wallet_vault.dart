import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feature_flags/feature_flags.dart';
import 'key_manager.dart';

/// Multi-wallet store, PR 1 of the mobile#8 design (Refs
/// wrfcoin/mobile-archive#434). Dark-launched behind
/// [FeatureFlags.enableMultiWallet]; with the flag off nothing here runs.
///
/// Owner rulings 2026-10-28: the station stays bound to the wallet it was
/// registered with, and that wallet cannot be removed. The legacy single-slot
/// wallet is the one the station was registered with (the station id is
/// derived from its address), so the migration marks it station-bound.
///
/// The vault uses the SAME [KeyValueStorage] as [KeyManager] (the
/// Keystore/Keychain-backed wallet store), so Emergency Wipe still removes
/// every copy. Key names carry a random wallet id, never an address or key.
/// Nothing in this file logs a slot value.
final walletVaultProvider = Provider<WalletVault>((ref) {
  return WalletVault(storage: ref.read(keyValueStorageProvider));
});

/// Runs the one-time migration when [FeatureFlags.enableMultiWallet] is on.
/// Never throws: on any failure the legacy slots are untouched and
/// [KeyManager] keeps reading them, so startup must not be blocked.
Future<WalletMigrationResult?> migrateWalletVaultIfEnabled(
  ProviderContainer container,
) async {
  if (!container.read(featureFlagsProvider).enableMultiWallet) return null;
  try {
    return await container.read(walletVaultProvider).migrateLegacy();
  } catch (e) {
    // Type only: an exception message is not trusted to be free of values.
    debugPrint('[WALLET_VAULT] migration failed: ${e.runtimeType}');
    return null;
  }
}

enum WalletMigrationResult {
  /// The legacy wallet was copied, verified and committed as the station
  /// wallet. The legacy slots are kept.
  migrated,

  /// The index already exists; nothing was read or written.
  alreadyMigrated,

  /// No legacy wallet (`wrf_address` absent); nothing was written.
  noLegacyWallet,

  /// The legacy mnemonic or private key did not read back; nothing was written.
  abortedIncompleteLegacy,

  /// A copied slot did not read back identically; the partial copy was
  /// removed and the legacy slots kept.
  abortedVerifyMismatch,
}

/// The vault refused to remove a wallet.
class WalletRemovalRefused implements Exception {
  const WalletRemovalRefused(this.reason);

  final WalletRemovalRefusal reason;

  @override
  String toString() => 'WalletRemovalRefused(${reason.name})';
}

enum WalletRemovalRefusal {
  /// Owner ruling 2026-10-28: the station-bound wallet cannot be removed.
  stationWallet,

  /// No such wallet id in the index.
  unknownWallet,

  /// The index is missing or unreadable, so the station binding cannot be
  /// checked. Fails closed.
  indexUnavailable,
}

/// One index entry. Holds an address, never key material.
class VaultWallet {
  const VaultWallet({
    required this.id,
    required this.label,
    required this.address,
    required this.createdAt,
    required this.stationBound,
  });

  final String id;
  final String label;
  final String address;
  final String createdAt;

  /// True for the wallet the station is registered to. Recorded in the same
  /// index write that commits the migration, so there is no window in which
  /// wallets exist without a station binding.
  final bool stationBound;

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'address': address,
    'createdAt': createdAt,
    'stationBound': stationBound,
  };

  static VaultWallet fromJson(Map<String, dynamic> json) {
    return VaultWallet(
      id: json['id'] as String,
      label: json['label'] as String,
      address: json['address'] as String,
      createdAt: json['createdAt'] as String,
      stationBound: json['stationBound'] == true,
    );
  }
}

class WalletVault {
  WalletVault({required this._storage, String Function()? newId})
    : _newId = newId ?? _randomId;

  final KeyValueStorage _storage;
  final String Function() _newId;

  static const indexKey = 'wrf_wallets_index';
  static const activeKey = 'wrf_wallets_active';

  /// Legacy single-slot key -> per-wallet field name. The auth session is not
  /// copied: it stays a single slot (design note, "Proposed storage layout").
  static const legacyFields = <String, String>{
    'wrf_mnemonic': 'mnemonic',
    'wrf_private_key': 'private_key',
    'wrf_address': 'address',
    'wrf_key_scheme': 'key_scheme',
    'wrf_login_private_key': 'login_private_key',
    'wrf_login_address': 'login_address',
    'wrf_backup_confirmed': 'backup_confirmed',
    'wrf_is_social': 'is_social',
  };

  static String slotKey(String walletId, String field) =>
      'wrf_w:$walletId:$field';

  static String _randomId() {
    final random = Random.secure();
    return List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Copy-verify-then-commit migration of the legacy single-slot wallet.
  ///
  /// 1. Read the legacy slots; abort with no writes unless the mnemonic and
  ///    private key both read back.
  /// 2. Copy them to a new wallet id (copy, never move).
  /// 3. Read every copied slot back; on any mismatch remove the partial copy
  ///    and abort.
  /// 4. Write the index (the commit point), then the active pointer.
  ///
  /// The legacy slots are never written. A kill anywhere before step 4 leaves
  /// no index, so the next run starts over and [KeyManager] reads legacy.
  Future<WalletMigrationResult> migrateLegacy() async {
    if (await _storage.read(key: indexKey) != null) {
      return _report(WalletMigrationResult.alreadyMigrated);
    }

    final legacy = <String, String?>{};
    for (final entry in legacyFields.entries) {
      legacy[entry.value] = await _storage.read(key: entry.key);
    }
    final address = legacy['address'];
    if (address == null) {
      return _report(WalletMigrationResult.noLegacyWallet);
    }
    if (legacy['mnemonic'] == null || legacy['private_key'] == null) {
      return _report(WalletMigrationResult.abortedIncompleteLegacy);
    }

    final id = _newId();
    // Absent legacy fields are written as null so stale slots from a killed
    // earlier attempt with the same id can never survive into the copy.
    for (final entry in legacy.entries) {
      await _storage.write(key: slotKey(id, entry.key), value: entry.value);
    }

    for (final entry in legacy.entries) {
      final copied = await _storage.read(key: slotKey(id, entry.key));
      if (copied != entry.value) {
        await _deleteSlots(id);
        return _report(WalletMigrationResult.abortedVerifyMismatch);
      }
    }

    final wallet = VaultWallet(
      id: id,
      label: 'Station wallet',
      address: address,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      stationBound: true,
    );
    await _storage.write(key: indexKey, value: jsonEncode([wallet.toJson()]));
    await _storage.write(key: activeKey, value: id);
    return _report(WalletMigrationResult.migrated);
  }

  /// Committed wallets, or null when the index is absent or unreadable.
  Future<List<VaultWallet>?> listWallets() async {
    final raw = await _storage.read(key: indexKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .map((e) => VaultWallet.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  /// The station-bound wallet, or null before migration.
  Future<VaultWallet?> stationWallet() async {
    final wallets = await listWallets();
    if (wallets == null) return null;
    for (final wallet in wallets) {
      if (wallet.stationBound) return wallet;
    }
    return null;
  }

  /// The active wallet id. Falls back to the station wallet when the pointer
  /// is missing (a kill between the index write and the pointer write) or
  /// names a wallet that is not in the index.
  Future<String?> activeWalletId() async {
    final wallets = await listWallets();
    if (wallets == null) return null;
    final active = await _storage.read(key: activeKey);
    if (active != null && wallets.any((w) => w.id == active)) return active;
    return (await stationWallet())?.id;
  }

  /// Reads one per-wallet slot. Returns null for an unknown wallet id.
  Future<String?> readSlot(String walletId, String field) async {
    final wallets = await listWallets();
    if (wallets == null || !wallets.any((w) => w.id == walletId)) return null;
    return _storage.read(key: slotKey(walletId, field));
  }

  /// Removes a wallet and its slots. Throws [WalletRemovalRefused] for the
  /// station-bound wallet (owner ruling 2026-10-28), for an unknown id, and
  /// when the index cannot be read. The index is rewritten before the slots
  /// are cleared, so a kill midway never leaves an indexed wallet without
  /// its keys.
  Future<void> removeWallet(String walletId) async {
    final wallets = await listWallets();
    if (wallets == null) {
      throw const WalletRemovalRefused(WalletRemovalRefusal.indexUnavailable);
    }
    final matches = wallets.where((w) => w.id == walletId).toList();
    if (matches.isEmpty) {
      throw const WalletRemovalRefused(WalletRemovalRefusal.unknownWallet);
    }
    if (matches.any((w) => w.stationBound)) {
      throw const WalletRemovalRefused(WalletRemovalRefusal.stationWallet);
    }

    final remaining = wallets.where((w) => w.id != walletId).toList();
    await _storage.write(
      key: indexKey,
      value: jsonEncode(remaining.map((w) => w.toJson()).toList()),
    );
    if (await _storage.read(key: activeKey) == walletId) {
      await _storage.write(key: activeKey, value: null);
    }
    await _deleteSlots(walletId);
  }

  Future<void> _deleteSlots(String walletId) async {
    for (final field in legacyFields.values) {
      await _storage.write(key: slotKey(walletId, field), value: null);
    }
  }

  WalletMigrationResult _report(WalletMigrationResult result) {
    debugPrint('[WALLET_VAULT] migration: ${result.name}');
    return result;
  }
}
