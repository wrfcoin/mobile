import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/crypto/ed25519_wallet_login.dart';
import 'package:wrfcoin_mobile/services/crypto/transparent_transfer_authorization.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

List<int> _unhex(String hex) => <int>[
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

const _expected = Ed25519LoginExpectation(
  origin: 'https://wallet.test',
  chainId: '777',
  network: 'testnet',
);
const _nonce = 'b3f1c2d4e5f60718293a4b5c6d7e8f90';

/// Byte-for-byte what backend#1208 `buildEd25519WalletLoginMessage` emits.
// Challenge timestamps relative to now: the wallet refuses expired challenges.
final String _issuedAt =
    DateTime.now().toUtc().subtract(const Duration(seconds: 1)).toIso8601String();
final String _expiresAt =
    DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String();

String _challenge({
  required String address,
  String origin = 'https://wallet.test',
  String chainId = '777',
  String network = 'testnet',
  String nonce = _nonce,
  String? issuedAt,
  String? expiresAt,
}) =>
    'wrfcoin_wallet_login_ed25519_v1\n'
    '${Uri.parse(origin).authority} wants you to sign in with your WRFCoin ed25519 account:\n'
    '$address\n\nSign in to WRFCoin Testnet.\n\n'
    'URI: $origin\nVersion: 1\nScheme: ed25519\nChain ID: $chainId\n'
    'Network: $network\nNonce: $nonce\n'
    'Issued At: ${issuedAt ?? _issuedAt}\n'
    'Expiration Time: ${expiresAt ?? _expiresAt}';

void main() {
  final vector = jsonDecode(
    File('contract-fixtures/wallet-key-scheme-vector.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final transferVector =
      (jsonDecode(
            File('contract-fixtures/transparent-transfer-auth-vector.json')
                .readAsStringSync(),
          ) as Map<String, dynamic>)['case']
          as Map<String, dynamic>;
  final address = vector['address'] as String;
  late String seed;

  setUpAll(() async {
    seed = (await WalletSetupService().importFromMnemonic(
      vector['mnemonic'] as String,
    )).privateKey;
  });

  Future<void> expectRefused(String message, {String? forAddress}) async {
    expect(
      ed25519LoginChallengeProblem(
        message: message,
        address: forAddress ?? address,
        nonce: _nonce,
        expected: _expected,
      ),
      isNotNull,
    );
    await expectLater(
      signEd25519WalletLogin(
        seedHex: seed,
        address: forAddress ?? address,
        nonce: _nonce,
        message: message,
        expected: _expected,
      ),
      throwsA(isA<Ed25519LoginChallengeRejected>()),
    );
  }

  test('signs the exact backend challenge for the vector wallet', () async {
    final message = _challenge(address: address);
    final proof = await signEd25519WalletLogin(
      seedHex: seed,
      address: address,
      nonce: _nonce,
      message: message,
      expected: _expected,
    );

    expect(proof.publicKeyHex, vector['ed25519_public_key_hex']);
    expect(proof.signatureHex, matches(RegExp(r'^[0-9a-f]{128}$')));
    // Plain ed25519 over the UTF-8 bytes of the server string.
    final ok = await Ed25519().verify(
      utf8.encode(message),
      signature: Signature(
        _unhex(proof.signatureHex),
        publicKey: SimplePublicKey(
          _unhex(proof.publicKeyHex),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    expect(ok, isTrue);
  });

  test(
    'refuses core4\'s golden transfer preimage offered as the message',
    () async {
      final preimage = _unhex(transferVector['preimage_hex'] as String);
      await expectRefused(String.fromCharCodes(preimage));
      await expectRefused(utf8.decode(preimage, allowMalformed: true));
    },
  );

  test(
    'refuses a transfer preimage that survives the JSON string round trip',
    () async {
      // backend#1208 review probe: this amount makes the preimage valid
      // UTF-8, so a server could deliver it as the "message" and the signed
      // bytes would be exactly the transfer authorization.
      final preimage = transparentTransferAuthorizationMessage(
        chainId: '777',
        networkId: 'testnet',
        from: address,
        to: '0x2222222222222222222222222222222222222222',
        amountBaseUnits: 547599908735,
        nonce: 7,
      );
      final asString = utf8.decode(preimage);
      expect(utf8.encode(asString), preimage);
      await expectRefused(asString);
      // Even with the login domain tag glued in front.
      await expectRefused('$ed25519WalletLoginDomain\n$asString');
    },
  );

  test('refuses a challenge for another address', () async {
    await expectRefused(
      _challenge(address: '0x1111111111111111111111111111111111111111'),
    );
    await expectRefused(_challenge(address: address.toUpperCase()));
  });

  test('refuses a key that does not control the address', () async {
    const other = '0x1111111111111111111111111111111111111111';
    await expectLater(
      signEd25519WalletLogin(
        seedHex: seed,
        address: other,
        nonce: _nonce,
        message: _challenge(address: other),
        expected: _expected,
      ),
      throwsA(isA<Ed25519LoginChallengeRejected>()),
    );
  });

  test('refuses a challenge without the exact domain-tag prefix', () async {
    final valid = _challenge(address: address);
    final withoutTag = valid.substring(valid.indexOf('\n') + 1);
    await expectRefused(withoutTag);
    await expectRefused(' $valid');
    await expectRefused(valid.replaceFirst('_v1\n', '_v2\n'));
    await expectRefused(valid.replaceFirst('_v1\n', '_v1\r\n'));
  });

  test('refuses the wrong origin, chain, network or nonce', () async {
    await expectRefused(
      _challenge(address: address, origin: 'https://evil.test'),
    );
    await expectRefused(
      _challenge(address: address, origin: 'http://wallet.test'),
    );
    await expectRefused(_challenge(address: address, chainId: '778'));
    await expectRefused(_challenge(address: address, network: 'mainnet'));
    await expectRefused(_challenge(address: address, nonce: 'other-nonce'));
  });

  test(
    'refuses extra, missing or reordered lines and bad timestamps',
    () async {
      final valid = _challenge(address: address);
      await expectRefused('$valid\nTransfer: 1000000 WRF');
      await expectRefused(valid.substring(0, valid.lastIndexOf('\n')));
      await expectRefused(
        valid.replaceFirst(
          'Version: 1\nScheme: ed25519',
          'Scheme: ed25519\nVersion: 1',
        ),
      );
      // Malformed expiry, and an expiry that is not after the issue time
      // (both judged at a clock before expiry, so only the shape fails).
      final at = DateTime.utc(2026, 9, 23, 0, 1);
      for (final message in [
        _challenge(
          address: address,
          issuedAt: '2026-09-23T00:00:00.000Z',
          expiresAt: 'never',
        ),
        _challenge(
          address: address,
          issuedAt: '2026-09-23T00:00:00.000Z',
          expiresAt: '2026-09-22T00:00:00.000Z',
        ),
      ]) {
        expect(
          ed25519LoginChallengeProblem(
            message: message,
            address: address,
            nonce: _nonce,
            expected: _expected,
            now: at,
          ),
          'bad challenge timestamps',
        );
        await expectRefused(message);
      }
    },
  );

  test('refuses an expired challenge without signing it', () async {
    final past = DateTime.now().toUtc();
    await expectRefused(
      _challenge(
        address: address,
        issuedAt: past.subtract(const Duration(minutes: 10)).toIso8601String(),
        expiresAt: past.subtract(const Duration(minutes: 5)).toIso8601String(),
      ),
    );
  });

  test('checks Expiration Time against the device clock (now)', () {
    final message = _challenge(
      address: address,
      issuedAt: '2026-09-23T00:00:00.000Z',
      expiresAt: '2026-09-23T00:05:00.000Z',
    );
    String? problemAt(DateTime now) => ed25519LoginChallengeProblem(
          message: message,
          address: address,
          nonce: _nonce,
          expected: _expected,
          now: now,
        );
    expect(problemAt(DateTime.utc(2026, 9, 23, 0, 4, 59)), isNull);
    expect(problemAt(DateTime.utc(2026, 9, 23, 0, 5)), 'challenge has expired');
    expect(problemAt(DateTime.utc(2026, 9, 24)), 'challenge has expired');
    // A non-UTC clock is normalised before comparing.
    expect(
      problemAt(DateTime.utc(2026, 9, 23, 0, 4, 59).toLocal()),
      isNull,
    );
  });

  test('refuses everything when no expected origin is configured', () async {
    final message = _challenge(address: address);
    for (final origin in ['', 'wallet.test', 'https://wallet.test/api']) {
      expect(
        ed25519LoginChallengeProblem(
          message: message,
          address: address,
          nonce: _nonce,
          expected: Ed25519LoginExpectation(
            origin: origin,
            chainId: '777',
            network: 'testnet',
          ),
        ),
        isNotNull,
        reason: origin,
      );
    }
  });

  test(
    'the default expected origin is the API base URL origin at 777/testnet',
    () {
      expect(
        Ed25519LoginExpectation.originOf('https://testnet.example/api'),
        'https://testnet.example',
      );
      expect(
        Ed25519LoginExpectation.originOf('http://localhost:4001/api'),
        'http://localhost:4001',
      );
      final configured = Ed25519LoginExpectation.configured();
      expect(configured.chainId, '888');
      expect(configured.network, 'testnet');
    },
  );
}
