import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/crypto/wallet_secure_storage.dart';
import '../../data/models/address_book_entry.dart';
import '../../domain/send_allowlist.dart';

final backupConfirmedProvider =
    AsyncNotifierProvider<BackupConfirmedNotifier, bool>(
      BackupConfirmedNotifier.new,
    );

class BackupConfirmedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.read(walletSecureStorageProvider).getBackupConfirmed();
  }

  Future<void> setConfirmed(bool confirmed) async {
    await ref.read(walletSecureStorageProvider).setBackupConfirmed(confirmed);
    state = AsyncData(confirmed);
  }
}

final socialWalletProvider = FutureProvider<bool>((ref) {
  return ref.read(walletSecureStorageProvider).getIsSocial();
});

/// The clock the send allowlist uses. Overridden in tests.
final allowlistClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final sendAllowlistPolicyProvider = Provider<SendAllowlistPolicy>((ref) {
  return SendAllowlistPolicy(clock: ref.watch(allowlistClockProvider));
});

final addressBookProvider =
    AsyncNotifierProvider<AddressBookNotifier, List<AddressBookEntry>>(
      AddressBookNotifier.new,
    );

/// The device-only address book. Nothing here reaches the network.
class AddressBookNotifier extends AsyncNotifier<List<AddressBookEntry>> {
  WalletSecureStorage get _storage => ref.read(walletSecureStorageProvider);

  @override
  Future<List<AddressBookEntry>> build() {
    return _storage.getAddressBook();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_storage.getAddressBook);
  }

  /// Adds a contact. A new contact is never allowed (allowing has its own
  /// cooldown); re-saving an existing address keeps its allowlist state.
  Future<void> addEntry(AddressBookEntry entry) async {
    final current = await _storage.getAddressBook();
    DateTime? keptAllowance;
    for (final e in current) {
      if (_key(e.address) == _key(entry.address)) keptAllowance = e.allowedFrom;
    }
    await _storage.addAddressBookEntry(
      keptAllowance == null
          ? entry.copyWith(clearAllowed: true)
          : entry.copyWith(allowedFrom: keptAllowance),
    );
    await refresh();
  }

  Future<void> addAll(List<AddressBookEntry> entries) async {
    final current = await _storage.getAddressBook();
    final known = {for (final e in current) _key(e.address)};
    await _storage.saveAddressBook([
      ...current,
      for (final e in entries)
        if (!known.contains(_key(e.address))) e.copyWith(clearAllowed: true),
    ]);
    await refresh();
  }

  Future<void> rename(String address, String label) =>
      _update(address, (e) => e.copyWith(label: label.trim()));

  Future<void> remove(String address) async {
    final current = await _storage.getAddressBook();
    await _storage.saveAddressBook([
      for (final e in current)
        if (_key(e.address) != _key(address)) e,
    ]);
    await refresh();
  }

  /// Allows [address] under the current allowlist settings (instant when the
  /// allowlist is off, after the cooldown when it is on).
  Future<void> allow(String address) async {
    final policy = ref.read(sendAllowlistPolicyProvider);
    final settings = await ref.read(sendAllowlistProvider.notifier).current();
    await _update(address, (e) => policy.allow(e, settings));
  }

  Future<void> revoke(String address) {
    final policy = ref.read(sendAllowlistPolicyProvider);
    return _update(address, policy.revoke);
  }

  Future<void> _update(
    String address,
    AddressBookEntry Function(AddressBookEntry) change,
  ) async {
    final current = await _storage.getAddressBook();
    await _storage.saveAddressBook([
      for (final e in current) _key(e.address) == _key(address) ? change(e) : e,
    ]);
    await refresh();
  }

  static String _key(String address) => address.trim().toLowerCase();
}

final sendAllowlistProvider =
    AsyncNotifierProvider<SendAllowlistNotifier, SendAllowlistSettings>(
      SendAllowlistNotifier.new,
    );

class SendAllowlistNotifier extends AsyncNotifier<SendAllowlistSettings> {
  WalletSecureStorage get _storage => ref.read(walletSecureStorageProvider);
  SendAllowlistPolicy get _policy => ref.read(sendAllowlistPolicyProvider);

  @override
  Future<SendAllowlistSettings> build() => current();

  /// Fresh settings from storage, with a due turn-off applied and saved.
  Future<SendAllowlistSettings> current() async {
    final stored = await _storage.getSendAllowlist();
    final settled = _policy.settle(stored);
    if (settled != stored) await _storage.saveSendAllowlist(settled);
    return settled;
  }

  Future<void> turnOn() => _apply(_policy.turnOn);
  Future<void> requestTurnOff() => _apply(_policy.requestTurnOff);
  Future<void> cancelTurnOff() => _apply(_policy.cancelTurnOff);

  Future<void> _apply(
    SendAllowlistSettings Function(SendAllowlistSettings) change,
  ) async {
    final next = change(await current());
    await _storage.saveSendAllowlist(next);
    state = AsyncData(next);
  }
}
