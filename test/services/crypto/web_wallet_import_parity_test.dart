import 'dart:convert';
import 'dart:io';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../../test_helpers/fakes.dart';

// Public synthetic vector shared by core4#3389, frontend#433 and mobile#376.
// W28 web creation uses deriveAccount(words, ''): no BIP-39 passphrase.
void main() {
  final vector = jsonDecode(
    File('contract-fixtures/transparent-transfer-auth-vector-777.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final signer = vector['signer'] as Map<String, dynamic>;
  final transfer = vector['case'] as Map<String, dynamic>;
  final words = signer['mnemonic'] as String;
  final service = WalletSetupService();

  test(
    '12-word web wallet imports with the same address and public key',
    () async {
      expect(words.split(' '), hasLength(12));
      final imported = await service.importFromMnemonic(words);
      expect(imported.address, transfer['from']);
      expect(imported.keyScheme, KeyManager.canonicalKeyScheme);
      final publicKey = await service.publicKeyFromEd25519Seed(
        imported.privateKey,
      );
      expect(
        publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        signer['ed25519_public_key_hex'],
      );
      expect(
        imported.privateKey,
        service.slip10Ed25519Seed(bip39.mnemonicToSeed(words, passphrase: '')),
      );
      final different = service.slip10Ed25519Seed(
        bip39.mnemonicToSeed(words, passphrase: 'synthetic-other-passphrase'),
      );
      expect(
        await service.chainAddressFromEd25519Seed(different),
        isNot(imported.address),
      );
    },
  );

  test('pasted web words preserve identity through phone storage', () async {
    final imported = await service.importFromMnemonic(
      '  ${words.toUpperCase().replaceAll(' ', '\n  ')}  ',
    );
    final keys = KeyManager(
      storage: InMemoryKeyValueStorage(),
      biometric: BiometricService(client: FakeLocalAuthClient()),
    );
    await keys.storeKeys(
      mnemonic: imported.mnemonic,
      privateKey: imported.privateKey,
      address: imported.address,
      keyScheme: imported.keyScheme,
    );
    expect(await keys.getAddress(), transfer['from']);
    expect(await keys.getKeyScheme(), KeyManager.canonicalKeyScheme);
    final recovered = await service.importFromMnemonic(
      (await keys.getMnemonic())!,
    );
    expect(recovered.address, transfer['from']);
    expect(recovered.privateKey, await keys.getPrivateKey());
  });
}
