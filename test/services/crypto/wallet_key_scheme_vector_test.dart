import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/digests/keccak.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

String hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final vector = jsonDecode(
    File('contract-fixtures/wallet-key-scheme-vector.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final service = WalletSetupService();

  test('pins the byte-identical core4 decision fixture', () {
    final bytes = File('contract-fixtures/wallet-key-scheme-vector.json')
        .readAsBytesSync();
    expect(
      crypto.sha256.convert(bytes).toString(),
      'b232464dea5cab623a481fb5eddbb2ec6a0cf04c6e8b80e590fe531f844b27d4',
    );
  });

  test('mobile reproduces the shared ed25519 wallet vector exactly', () async {
    final wallet = await service.importFromMnemonic(
      vector['mnemonic'] as String,
    );
    final publicKey = await service.publicKeyFromEd25519Seed(wallet.privateKey);

    expect(hex(publicKey), vector['ed25519_public_key_hex']);
    expect(wallet.address, vector['address']);
    expect(wallet.address, service.chainAddressFromEd25519(publicKey));
  });

  test('address uses SHA3-256, not Keccak-256', () async {
    final wallet = await service.importFromMnemonic(
      vector['mnemonic'] as String,
    );
    final publicKey = await service.publicKeyFromEd25519Seed(wallet.privateKey);
    final keccak = KeccakDigest(256).process(Uint8List.fromList(publicKey));
    final mutatedAddress = '0x${hex(keccak.take(20))}';

    expect(mutatedAddress, isNot(vector['address']));
    expect(wallet.address, vector['address']);
  });

  test(
    'legacy sha256 shortcut differs from the decided SLIP-0010 seed',
    () async {
      final mnemonic = vector['mnemonic'] as String;
      final wallet = await service.importFromMnemonic(mnemonic);
      expect(
        service.legacyPrivateKeyFromMnemonic(mnemonic),
        isNot(wallet.privateKey),
      );
    },
  );
}
