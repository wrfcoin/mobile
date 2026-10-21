import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

void main() {
  group('WalletSetupService', () {
    late WalletSetupService service;

    setUp(() {
      service = WalletSetupService();
    });

    test('generateWallet returns 12-word mnemonic and derived keys', () async {
      final result = await service.generateWallet();

      expect(result.mnemonic.split(' ').length, 12);
      expect(result.privateKey.startsWith('0x'), true);
      expect(result.address, matches(RegExp(r'^0x[a-f0-9]{40}$')));
      expect(result.keyScheme, WalletSetupService.keyScheme);
      // ed25519 wallets log in with their own key (backend#1208): no
      // separate secp256k1 login identity is derived.
      expect(result.loginPrivateKey, isNull);
      expect(result.loginAddress, isNull);
    });

    test('importFromMnemonic derives deterministic chain address', () async {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

      final first = await service.importFromMnemonic(mnemonic);
      final second = await service.importFromMnemonic(mnemonic);

      expect(first.address, equals(second.address));
      expect(first.address, matches(RegExp(r'^0x[a-f0-9]{40}$')));
      expect(first.loginPrivateKey, isNull);
      expect(first.loginAddress, isNull);
    });

    test('importFromPrivateKey preserves the legacy wallet and marks it receive-only', () async {
      const privateKey =
          '0x0000000000000000000000000000000000000000000000000000000000000001';

      final result = await service.importFromPrivateKey(privateKey);

      expect(result.privateKey, privateKey);
      expect(result.address, '0x7e5f4552091a69125d5dfcb7b8c2659029395bdf');
      expect(result.keyScheme, KeyManager.legacyKeyScheme);
      expect(result.loginPrivateKey, privateKey);
      expect(result.loginAddress, result.address);
    });

    test('importFromPrivateKey accepts unprefixed 32-byte hex keys', () async {
      const privateKey =
          '0000000000000000000000000000000000000000000000000000000000000001';

      final result = await service.importFromPrivateKey(privateKey);

      expect(result.privateKey, '0x$privateKey');
      expect(result.address, '0x7e5f4552091a69125d5dfcb7b8c2659029395bdf');
      expect(result.keyScheme, KeyManager.legacyKeyScheme);
    });

    test(
      'importFromPrivateKey rejects non-hex keys instead of hashing them',
      () {
        expect(
          () => service.importFromPrivateKey('not-a-private-key'),
          throwsArgumentError,
        );
      },
    );

    test('pickVerificationIndexes returns unique indexes within range', () {
      final indexes = service.pickVerificationIndexes(
        12,
        count: 3,
        random: Random(7),
      );

      expect(indexes, hasLength(3));
      expect(indexes.toSet().length, 3);
      expect(indexes.every((index) => index >= 0 && index < 12), isTrue);
    });

    test(
      'pickVerificationIndexes returns all indexes when count exceeds size',
      () {
        final indexes = service.pickVerificationIndexes(2, count: 3);
        expect(indexes, [0, 1]);
      },
    );

    test('verifyMnemonicSelections matches normalized words', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

      expect(
        service.verifyMnemonicSelections(
          mnemonic: mnemonic,
          indexes: const [0, 11],
          responses: const {0: 'Abandon', 11: 'ABOUT'},
        ),
        isTrue,
      );
    });

    test('verifyMnemonicSelections rejects mismatched words', () {
      const mnemonic =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

      expect(
        service.verifyMnemonicSelections(
          mnemonic: mnemonic,
          indexes: const [0, 11],
          responses: const {0: 'abandon', 11: 'wrong'},
        ),
        isFalse,
      );
    });
  });
}
