import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/crypto/wallet_secure_storage.dart';
import '../../data/models/address_book_entry.dart';

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

final addressBookProvider =
    AsyncNotifierProvider<AddressBookNotifier, List<AddressBookEntry>>(
      AddressBookNotifier.new,
    );

class AddressBookNotifier extends AsyncNotifier<List<AddressBookEntry>> {
  @override
  Future<List<AddressBookEntry>> build() {
    return ref.read(walletSecureStorageProvider).getAddressBook();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(walletSecureStorageProvider).getAddressBook(),
    );
  }

  Future<void> addEntry(AddressBookEntry entry) async {
    await ref.read(walletSecureStorageProvider).addAddressBookEntry(entry);
    await refresh();
  }
}
