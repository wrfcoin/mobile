import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'package:web3dart/credentials.dart';

import 'key_manager.dart';

final walletSetupServiceProvider = Provider<WalletSetupService>((ref) {
  return WalletSetupService();
});

class WalletCredentials {
  final String mnemonic;
  final String privateKey;
  final String address;
  final String keyScheme;

  /// Separate secp256k1 login identity. Only set for receive-only
  /// private-key imports; ed25519 wallets log in with their own key
  /// (backend#1208), so [KeyManager.storeKeys] defaults these to
  /// [privateKey] / [address].
  final String? loginPrivateKey;
  final String? loginAddress;

  const WalletCredentials({
    required this.mnemonic,
    required this.privateKey,
    required this.address,
    required this.keyScheme,
    this.loginPrivateKey,
    this.loginAddress,
  });
}

// Security: wallet generation is always on-device. Private keys never leave
// the device. Server-side generation was removed in #85 because it transmitted
// mnemonic and private key over HTTP.
class WalletSetupService {
  WalletSetupService();

  static const keyScheme = 'ed25519-slip10';

  Future<WalletCredentials> generateWallet() async {
    final mnemonic = bip39.generateMnemonic();
    final privateKey = slip10Ed25519Seed(bip39.mnemonicToSeed(mnemonic));
    final address = await chainAddressFromEd25519Seed(privateKey);

    return WalletCredentials(
      mnemonic: mnemonic,
      privateKey: privateKey,
      address: address,
      keyScheme: keyScheme,
    );
  }

  Future<WalletCredentials> importFromMnemonic(String mnemonic) async {
    final normalized = mnemonic.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (!bip39.validateMnemonic(normalized)) {
      throw ArgumentError('Invalid mnemonic phrase');
    }

    final privateKey = slip10Ed25519Seed(bip39.mnemonicToSeed(normalized));
    final address = await chainAddressFromEd25519Seed(privateKey);

    return WalletCredentials(
      mnemonic: normalized,
      privateKey: privateKey,
      address: address,
      keyScheme: keyScheme,
    );
  }

  Future<WalletCredentials> importFromPrivateKey(String privateKey) async {
    final normalized = privateKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Private key required');
    }

    final canonicalKey = _normalizePrivateKey(normalized);
    // A raw 32-byte key has no scheme marker. Preserve the established
    // secp256k1 interpretation and classify it receive-only for chain sends;
    // silently treating it as an ed25519 seed would produce a different wallet.
    final address = EthPrivateKey.fromHex(canonicalKey).address.hex;

    final syntheticMnemonic = 'imported private key ${address.substring(0, 8)}';

    return WalletCredentials(
      mnemonic: syntheticMnemonic,
      privateKey: canonicalKey,
      address: address,
      keyScheme: KeyManager.legacyKeyScheme,
      loginPrivateKey: canonicalKey,
      loginAddress: address,
    );
  }

  List<int> pickVerificationIndexes(
    int length, {
    required int count,
    Random? random,
  }) {
    if (length <= 0 || count <= 0) return const [];
    if (length <= count) {
      return List<int>.generate(length, (index) => index);
    }

    final values = <int>{};
    final picker = random ?? Random.secure();
    while (values.length < count) {
      values.add(picker.nextInt(length));
    }
    final sorted = values.toList()..sort();
    return sorted;
  }

  bool verifyMnemonicSelections({
    required String mnemonic,
    required List<int> indexes,
    required Map<int, String> responses,
  }) {
    final words = mnemonic.trim().split(RegExp(r'\s+'));
    for (final index in indexes) {
      if (index < 0 || index >= words.length) return false;
      final expected = words[index].trim().toLowerCase();
      final actual = responses[index]?.trim().toLowerCase() ?? '';
      if (expected != actual) return false;
    }
    return true;
  }

  /// The pre-decision secp256k1 shortcut, retained only for explicit legacy
  /// detection/migration tests. It must never create a new wallet.
  String legacyPrivateKeyFromMnemonic(String mnemonic) {
    final seedHex = bip39.mnemonicToSeedHex(mnemonic);
    return '0x${crypto.sha256.convert(utf8.encode(seedHex)).toString()}';
  }

  /// SLIP-0010 ed25519 master key: HMAC-SHA512("ed25519 seed", BIP39 seed),
  /// first 32 bytes, with no child derivation path (core4#3234).
  String slip10Ed25519Seed(Uint8List bip39Seed) {
    final digest = crypto.Hmac(
      crypto.sha512,
      utf8.encode('ed25519 seed'),
    ).convert(bip39Seed);
    return '0x${_hex(digest.bytes.take(32))}';
  }

  Future<Uint8List> publicKeyFromEd25519Seed(String privateKey) async {
    final seed = _hexBytes(_normalizePrivateKey(privateKey).substring(2));
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = await pair.extractPublicKey();
    return Uint8List.fromList(publicKey.bytes);
  }

  Future<String> chainAddressFromEd25519Seed(String privateKey) async {
    final publicKey = await publicKeyFromEd25519Seed(privateKey);
    return chainAddressFromEd25519(publicKey);
  }

  String chainAddressFromEd25519(Uint8List publicKey) {
    if (publicKey.length != 32) {
      throw ArgumentError('Ed25519 public key must be 32 bytes');
    }
    final digest = SHA3Digest(256).process(publicKey);
    return '0x${_hex(digest.take(20))}';
  }

  static String _hex(Iterable<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexBytes(String value) => Uint8List.fromList([
    for (var offset = 0; offset < value.length; offset += 2)
      int.parse(value.substring(offset, offset + 2), radix: 16),
  ]);

  String _normalizePrivateKey(String privateKey) {
    final trimmed = privateKey.trim();
    final clean = trimmed.toLowerCase().startsWith('0x')
        ? trimmed.substring(2)
        : trimmed;
    final normalized = clean.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw ArgumentError('Private key must be a 32-byte hex value');
    }
    return '0x$normalized';
  }
}
