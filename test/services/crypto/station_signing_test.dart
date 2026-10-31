import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../../test_helpers/fakes.dart';

// Golden vectors. Synthetic test keys only; they control no real account.
//
// Preimage A, preimage B and the station id: copied from backend
//   wrfcoin/backend @ 86b6e945  __tests__/mobile-station-golden.test.ts
//   (CORE4 const :23-31, station id :95).
// Preimage A v2 (adds collect_pubkey, domain ..._reg_v2): copied from backend
//   branch feat/1288-b6-collect-key, __tests__/mobile-station-golden.test.ts
//   EXPECTED_A_V2 (assembled independently in Python; the same script
//   reproduces the retired v1 vector byte for byte).
// Preimage B and its signature were produced by core4's own
//   station_ownership_message_with_domain + PrivateKey::sign, seed [7u8; 32].
// Commit authorization v2: core4 shared-protocol/tests/fixtures/golden/
//   signing_preimage_v2.json, case kind `commit_authorization_v2`
//   (signer_seed 900101), also pinned by backend
//   __tests__/commit-authorization-golden.test.ts:19-39.
const _seedHex =
    '0707070707070707070707070707070707070707070707070707070707070707';
const _publicKeyHex =
    'ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c';
const _ownerAddress = '0x791026e25cc1ba461167ffb5c6dc095c284bd92c';
const _goldenIdStation = 'mob-0123456789abcdef0123456789abcdef';
const _derivedStationId = 'mob-7fe8d26b9fe9c060ea559732d5a6033e';
const _ownershipMessageHex =
    '777266636f696e5f73746174696f6e5f6f776e6572736869705f76310300000037373707000000746573746e6574240000006d6f622d30313233343536373839616263646566303132333435363738396162636465662a000000307837393130323665323563633162613436313136376666623563366463303935633238346264393263';
const _ownershipSignatureHex =
    '4983b317ac64e109c15426fa4378452bd0053838a27e12608a4c1242280fd9c0b5fe97437f65bce97b8e24876ea81da33e8b9eae5f8ab173bbd8ebd597e4210a';
const _registrationMessageHex =
    '777266636f696e5f6d6f62696c655f73746174696f6e5f7265675f76320300000037373707000000746573746e6574240000006d6f622d30313233343536373839616263646566303132333435363738396162636465662a00000030783739313032366532356363316261343631313637666662356336646330393563323834626439326340000000303130323033303430353036303730383039306130623063306430653066313031313132313331343135313631373138313931613162316331643165316632307b00000038feffff170000006e6f6e63652d676f6c64656e2d30303030303030303031ac3cb16a00000000';
// The synthetic collect key of the A v2 vector: bytes 0x01..0x20.
const _collectPubkey =
    '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';

const _commitSeedHex =
    '141fa03a9a9fb8e4b6a5dd30640c734c6425ee487b91cd5ec0057cd519ec492a';
const _commitPublicKeyHex =
    '87d795e0f67a76f42590f20b9a9a2495513962ebc798f94ccc697b3d5e833abf';
const _commitPreimageHex =
    '777266636f696e5f636f6d6d69745f617574685f76320f000000777266636f696e2d746573746e657407000000746573746e65740c00000073746174696f6e2d67762d3110000000636f6d6d69742d67762d617574682d310700000077656174686572';
const _commitSignatureHex =
    'e7d9e3d36719c67da9c110d6ab3544b5d19232c11ba0a94eab319104e655f3c53a6ba9c1625f0c01ce2228fd3ab3dc360b14dc4cd02bb8812f2a467febafbb04';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

Future<bool> _verify(String pubHex, String sigHex, List<int> msg) =>
    Ed25519().verify(
      msg,
      signature: Signature(
        _unhex(sigHex),
        publicKey: SimplePublicKey(_unhex(pubHex), type: KeyPairType.ed25519),
      ),
    );

/// Counts reads of the (biometric-gated) private key entry.
class _CountingStorage extends InMemoryKeyValueStorage {
  int privateKeyReads = 0;

  @override
  Future<String?> read({required String key}) {
    if (key == 'wrf_private_key') privateKeyReads++;
    return super.read(key: key);
  }
}

/// The core4/backend golden vectors here were produced for chain 777; replay
/// them at that domain, not the build's configured (888) default.
const _vectorDomain = TransferSigningDomain(
  chainId: '777',
  networkId: 'testnet',
);

void main() {
  group('deriveMobileStationId (M1)', () {
    test('matches the backend golden vector', () {
      expect(deriveMobileStationId(_ownerAddress), _derivedStationId);
    });

    test('is case/whitespace-insensitive on the address like the backend', () {
      expect(
        deriveMobileStationId(
          '  ${_ownerAddress.toUpperCase().replaceFirst('0X', '0x')} ',
        ),
        _derivedStationId,
      );
    });

    test('rejects non-chain addresses', () {
      for (final bad in ['', 'wrf1abc', '0x123', '0x${'g' * 40}', 'a' * 40]) {
        expect(() => deriveMobileStationId(bad), throwsArgumentError);
      }
    });

    test(
      'a different address or slot gives a different id; shape is mob-+32hex',
      () {
        final other = deriveMobileStationId('0x${'1' * 40}');
        expect(other, isNot(_derivedStationId));
        expect(other, matches(RegExp(r'^mob-[0-9a-f]{32}$')));
        expect(
          deriveMobileStationId(_ownerAddress, slot: 1),
          isNot(_derivedStationId),
        );
      },
    );
  });

  group('preimages', () {
    test(
      'B (station ownership) equals core4 bytes; core4 signature verifies',
      () async {
        final msg = stationOwnershipMessage(
          chainId: '777',
          networkId: 'testnet',
          stationId: _goldenIdStation,
          ownerAddress: _ownerAddress,
        );
        expect(_hex(msg), _ownershipMessageHex);
        expect(
          await _verify(_publicKeyHex, _ownershipSignatureHex, msg),
          isTrue,
        );
      },
    );

    test(
      'B tampering any field breaks bytes and the core4 signature',
      () async {
        final variants = <Map<String, String>>[
          {'stationId': 'mob-0123456789abcdef0123456789abcdee'},
          {'ownerAddress': '0x791026e25cc1ba461167ffb5c6dc095c284bd92d'},
          {'chainId': '778'},
          {'networkId': 'mainnet'},
        ];
        for (final v in variants) {
          final msg = stationOwnershipMessage(
            chainId: v['chainId'] ?? '777',
            networkId: v['networkId'] ?? 'testnet',
            stationId: v['stationId'] ?? _goldenIdStation,
            ownerAddress: v['ownerAddress'] ?? _ownerAddress,
          );
          expect(_hex(msg), isNot(_ownershipMessageHex));
          expect(
            await _verify(_publicKeyHex, _ownershipSignatureHex, msg),
            isFalse,
          );
        }
      },
    );

    test(
      'A (mobile registration) equals backend bytes, negative lon included',
      () {
        final msg = mobileStationRegistrationMessage(
          chainId: '777',
          networkId: 'testnet',
          stationId: _goldenIdStation,
          ownerAddress: _ownerAddress,
          collectPubkey: _collectPubkey,
          latE1: 123,
          lonE1: -456,
          nonce: 'nonce-golden-0000000001',
          expiresAt: 1790000300,
        );
        expect(_hex(msg), _registrationMessageHex);
      },
    );

    test('A tampering any field changes the bytes', () {
      MobileStationRegistrationArgs base() =>
          const MobileStationRegistrationArgs(
            chainId: '777',
            networkId: 'testnet',
            stationId: _goldenIdStation,
            ownerAddress: _ownerAddress,
            collectPubkey: _collectPubkey,
            latE1: 123,
            lonE1: -456,
            nonce: 'nonce-golden-0000000001',
            expiresAt: 1790000300,
          );
      final golden = _registrationMessageHex;
      final variants = <MobileStationRegistrationArgs>[
        base().copyWith(chainId: '778'),
        base().copyWith(networkId: 'mainnet'),
        base().copyWith(stationId: 'mob-0123456789abcdef0123456789abcdee'),
        base().copyWith(
          ownerAddress: '0x791026e25cc1ba461167ffb5c6dc095c284bd92d',
        ),
        base().copyWith(collectPubkey: '02${_collectPubkey.substring(2)}'),
        base().copyWith(latE1: 124),
        base().copyWith(lonE1: -455),
        base().copyWith(nonce: 'nonce-golden-0000000002'),
        base().copyWith(expiresAt: 1790000301),
      ];
      for (final v in variants) {
        expect(_hex(v.message()), isNot(golden));
      }
    });

    test('A rejects out-of-range integers rather than truncating', () {
      const ok = MobileStationRegistrationArgs(
        chainId: '777',
        networkId: 'testnet',
        stationId: _goldenIdStation,
        ownerAddress: _ownerAddress,
        collectPubkey: _collectPubkey,
        latE1: 0,
        lonE1: 0,
        nonce: 'n',
        expiresAt: 1,
      );
      expect(() => ok.copyWith(latE1: 1 << 31).message(), throwsArgumentError);
      expect(
        () => ok.copyWith(lonE1: -(1 << 31) - 1).message(),
        throwsArgumentError,
      );
      expect(() => ok.copyWith(expiresAt: -1).message(), throwsArgumentError);
    });

    test(
      'commit authorization v2 equals core4 golden; golden signature verifies',
      () async {
        final msg = commitAuthorizationMessage(
          chainId: 'wrfcoin-testnet',
          networkId: 'testnet',
          stationId: 'station-gv-1',
          commitId: 'commit-gv-auth-1',
          contributionType: 'weather',
        );
        expect(_hex(msg), _commitPreimageHex);
        expect(
          await _verify(_commitPublicKeyHex, _commitSignatureHex, msg),
          isTrue,
        );
      },
    );

    test(
      'commit authorization tampering breaks the golden signature',
      () async {
        final base = <String, String>{
          'chainId': 'wrfcoin-testnet',
          'networkId': 'testnet',
          'stationId': 'station-gv-1',
          'commitId': 'commit-gv-auth-1',
          'contributionType': 'weather',
        };
        for (final key in base.keys) {
          final v = {...base, key: '${base[key]}x'};
          final msg = commitAuthorizationMessage(
            chainId: v['chainId']!,
            networkId: v['networkId']!,
            stationId: v['stationId']!,
            commitId: v['commitId']!,
            contributionType: v['contributionType']!,
          );
          expect(_hex(msg), isNot(_commitPreimageHex), reason: key);
          expect(
            await _verify(_commitPublicKeyHex, _commitSignatureHex, msg),
            isFalse,
            reason: key,
          );
        }
        // moving bytes between adjacent fields must change the preimage
        expect(
          _hex(
            commitAuthorizationMessage(
              chainId: '777',
              networkId: 'testnet',
              stationId: 'ab',
              commitId: 'c',
              contributionType: 'contribution',
            ),
          ),
          isNot(
            _hex(
              commitAuthorizationMessage(
                chainId: '777',
                networkId: 'testnet',
                stationId: 'a',
                commitId: 'bc',
                contributionType: 'contribution',
              ),
            ),
          ),
        );
      },
    );

    test('lengths count UTF-8 bytes, not code units', () {
      final msg = commitAuthorizationMessage(
        chainId: '777',
        networkId: 'testnet',
        stationId: 'é',
        commitId: 'c',
        contributionType: 'contribution',
      );
      final off = 'wrfcoin_commit_auth_v2'.length + 4 + 3 + 4 + 7;
      expect(ByteData.sublistView(msg).getUint32(off, Endian.little), 2);
    });
  });

  group('StationSigningService (M2)', () {
    late InMemoryKeyValueStorage storage;

    KeyManager manager({bool auth = true}) => KeyManager(
      biometric: BiometricService(
        client: FakeLocalAuthClient(authenticateResult: auth),
      ),
      storage: storage,
    );

    Future<KeyManager> walletWith(String seedHex, String address) async {
      final m = manager();
      await m.storeKeys(
        mnemonic: 'synthetic',
        privateKey: seedHex,
        address: address,
      );
      return m;
    }

    setUp(() => storage = InMemoryKeyValueStorage());

    test(
      'signs A, B and commit auth; signatures verify and match core4 for B',
      () async {
        final km = await walletWith(_seedHex, _ownerAddress);
        final service = StationSigningService(
          keyManager: km,
          domain: _vectorDomain,
          isForeground: () => true,
        );
        final session = await service.openSession();
        expect(session, isNotNull);
        expect(session!.publicKeyHex, _publicKeyHex);
        expect(session.ownerAddress, _ownerAddress);
        expect(session.stationId, _derivedStationId);

        final own = await session.signOwnership();
        expect(own.message.length, greaterThan(0));
        expect(
          await _verify(_publicKeyHex, own.signatureHex, own.message),
          isTrue,
        );
        // The id is derived, so re-derive the golden-id preimage directly to
        // compare against core4's signature (Ed25519 is deterministic).
        final golden = await session.signOwnershipFor(
          stationId: _goldenIdStation,
        );
        expect(_hex(golden.message), _ownershipMessageHex);
        expect(golden.signatureHex, _ownershipSignatureHex);

        final reg = await session.signRegistration(
          collectPubkey: _collectPubkey,
          latE1: 123,
          lonE1: -456,
          nonce: 'nonce-golden-0000000001',
          expiresAt: 1790000300,
        );
        expect(
          await _verify(_publicKeyHex, reg.signatureHex, reg.message),
          isTrue,
        );

        // The wallet session has no commit-signing API at all (design §11):
        // commit authorizations belong to the collect key.
        // ignore: avoid_dynamic_calls
        expect(() => (session as dynamic).signCommitAuthorization(commitId: 'c'),
            throwsNoSuchMethodError);
      },
    );

    test('commit auth signature equals the core4 golden signature (same key/preimage)', () async {
      final signer = await Ed25519TransferSigner.fromSeedHex(_commitSeedHex);
      final r = commitAuthorizationMessage(
        chainId: 'wrfcoin-testnet',
        networkId: 'testnet',
        stationId: 'station-gv-1',
        commitId: 'commit-gv-auth-1',
        contributionType: 'weather',
      );
      expect(_hex(r), _commitPreimageHex);
      expect(_hex(await signer.sign(r)), _commitSignatureHex);
    });

    test(
      'returns null when biometric auth is refused; no signing possible',
      () async {
        await walletWith(_seedHex, _ownerAddress);
        final refused = StationSigningService(
          keyManager: manager(auth: false),
          domain: _vectorDomain,
          isForeground: () => true,
        );
        // storage is shared, so the refusing manager still sees the wallet.
        expect(await refused.openSession(), isNull);
      },
    );

    test(
      'refuses outside the foreground (design Q5) without touching the key',
      () async {
        // Count real reads of the stored private key (not isForeground calls).
        final counting = _CountingStorage();
        storage = counting;
        final km = await walletWith(_seedHex, _ownerAddress);
        counting.privateKeyReads = 0;

        final background = StationSigningService(
          keyManager: km,
          domain: _vectorDomain,
          isForeground: () => false,
        );
        await expectLater(
          background.openSession(),
          throwsA(isA<StationSigningForegroundRequired>()),
        );
        expect(counting.privateKeyReads, 0);

        // Positive control: the counter does see the foreground read.
        final foreground = StationSigningService(
          keyManager: km,
          domain: _vectorDomain,
          isForeground: () => true,
        );
        expect(await foreground.openSession(), isNotNull);
        expect(counting.privateKeyReads, 1);
      },
    );

    test('refuses a legacy (non-ed25519) wallet', () async {
      await storage.write(key: 'wrf_address', value: _ownerAddress);
      final service = StationSigningService(
        keyManager: manager(),
        domain: _vectorDomain,
        isForeground: () => true,
      );
      await expectLater(
        service.openSession(),
        throwsA(isA<StationSigningUnavailable>()),
      );
    });

    test(
      'refuses when the stored address does not derive from the seed',
      () async {
        final km = await walletWith(_seedHex, '0x${'1' * 40}');
        final service = StationSigningService(
          keyManager: km,
          domain: _vectorDomain,
          isForeground: () => true,
        );
        await expectLater(
          service.openSession(),
          throwsA(isA<StationSigningUnavailable>()),
        );
      },
    );

    test('a closed session cannot sign', () async {
      final km = await walletWith(_seedHex, _ownerAddress);
      final session = (await StationSigningService(
        keyManager: km,
        domain: _vectorDomain,
        isForeground: () => true,
      ).openSession())!;
      session.close();
      await expectLater(session.signOwnership(), throwsStateError);
    });

    test(
      'never logs the seed, public-key-derived secrets or signatures',
      () async {
        final logs = <String?>[];
        final original = debugPrint;
        debugPrint = (m, {wrapWidth}) => logs.add(m);
        try {
          final km = await walletWith(_seedHex, _ownerAddress);
          final session = (await StationSigningService(
            keyManager: km,
            domain: _vectorDomain,
            isForeground: () => true,
          ).openSession())!;
          final sigs = [(await session.signOwnership()).signatureHex];
          session.close();
          final joined = logs.join('\n');
          expect(joined.contains(_seedHex), isFalse);
          for (final s in sigs) {
            expect(joined.contains(s), isFalse);
          }
          expect(session.toString().contains(_seedHex), isFalse);
        } finally {
          debugPrint = original;
        }
      },
    );
  });
}
