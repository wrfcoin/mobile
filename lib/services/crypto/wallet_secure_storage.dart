import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/wallet/data/models/address_book_entry.dart';
import '../../features/wallet/domain/send_allowlist.dart';

final walletSecureStorageProvider = Provider<WalletSecureStorage>((ref) {
  return const WalletSecureStorage();
});

/// Wallet metadata kept only on this device. The address book and the send
/// allowlist live here and are never sent to a server.
class WalletSecureStorage {
  const WalletSecureStorage();

  static const _storage = FlutterSecureStorage();

  static const addressKey = 'wrf_address';
  static const backupConfirmedKey = 'wrf_backup_confirmed';
  static const isSocialKey = 'wrf_is_social';
  static const addressBookKey = 'wrf_address_book';
  static const sendAllowlistKey = 'wrf_send_allowlist';

  Future<String?> getWalletAddress() => _storage.read(key: addressKey);

  Future<bool> getBackupConfirmed() async {
    return (await _storage.read(key: backupConfirmedKey)) == 'true';
  }

  Future<void> setBackupConfirmed(bool confirmed) {
    return _storage.write(key: backupConfirmedKey, value: confirmed.toString());
  }

  Future<bool> getIsSocial() async {
    return (await _storage.read(key: isSocialKey)) == 'true';
  }

  Future<void> setIsSocial(bool isSocial) {
    return _storage.write(key: isSocialKey, value: isSocial.toString());
  }

  Future<List<AddressBookEntry>> getAddressBook() async {
    final raw = await _storage.read(key: addressBookKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((rawItem) => Map<String, dynamic>.from(rawItem))
          .map(AddressBookEntry.fromJson)
          .where((entry) => entry.label.isNotEmpty && entry.address.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAddressBook(List<AddressBookEntry> entries) {
    final payload = jsonEncode(entries.map((e) => e.toJson()).toList());
    return _storage.write(key: addressBookKey, value: payload);
  }

  Future<SendAllowlistSettings> getSendAllowlist() async {
    final raw = await _storage.read(key: sendAllowlistKey);
    if (raw == null || raw.isEmpty) return SendAllowlistSettings.off;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return SendAllowlistSettings.off;
      return SendAllowlistSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return SendAllowlistSettings.off;
    }
  }

  Future<void> saveSendAllowlist(SendAllowlistSettings settings) {
    return _storage.write(
      key: sendAllowlistKey,
      value: jsonEncode(settings.toJson()),
    );
  }

  Future<void> clearWalletData() async {
    await Future.wait([
      _storage.delete(key: addressKey),
      _storage.delete(key: backupConfirmedKey),
      _storage.delete(key: isSocialKey),
      _storage.delete(key: addressBookKey),
      _storage.delete(key: sendAllowlistKey),
    ]);
  }

  Future<void> addAddressBookEntry(AddressBookEntry entry) async {
    final entries = await getAddressBook();
    final normalizedAddress = entry.address.toLowerCase();

    final filtered = entries
        .where((e) => e.address.toLowerCase() != normalizedAddress)
        .toList(growable: true);
    filtered.insert(0, entry);
    await saveAddressBook(filtered);
  }
}
