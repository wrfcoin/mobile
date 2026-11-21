import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../../features/collector/station_owner_fixtures.dart';

// set_submitter_key preimage (core4 main 46e9de9,
// shared-protocol/src/blockchain/transaction.rs
// `station_owner_set_submitter_message_with_domain`, ~:1365).
//
// core4 has NO fixed-byte golden for this message yet: its test
// (shared-protocol/tests/station_submitter_key.rs:208-226) checks the layout
// structurally (base action bytes with discriminant 5, then flag, lv(key),
// class). These hex strings were HAND-DERIVED from that code with an
// independent Python encoder whose base bytes reproduce the core4 report_stolen
// golden (`_actionHex` in station_owner_signing_test.dart) exactly. Replace
// them with a core4-published golden once one lands.
const _chain = 'wrfcoin-testnet';
const _network = 'testnet';
const _station = 'station-golden-3347';
final _a1 = 'wrf${'a1' * 20}';
final _key = 'b3' * 32;

const _base =
    '777266636f696e5f73746174696f6e5f6f776e65725f616374696f6e5f76310f0000'
    '00777266636f696e2d746573746e657407000000746573746e657413000000737461'
    '74696f6e2d676f6c64656e2d333334372b0000007772666131613161316131613161'
    '31613161316131613161316131613161316131613161316131613161310507000000'
    '000000000852000000000000';
const _keyLv =
    '40000000623362336233623362336233623362336233623362336233623362336233'
    '62336233623362336233623362336233623362336233623362336233623362336233';
const _setDeviceHex = '${_base}01${_keyLv}01';
const _setRelayHex = '${_base}01${_keyLv}02';
const _clearHex = '${_base}00';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> _msg({String? key, SubmitterClass? cls, int nonce = 7}) =>
    stationOwnerSetSubmitterMessage(
      chainId: _chain,
      networkId: _network,
      stationId: _station,
      ownerAddress: _a1,
      actionNonce: nonce,
      expiresAtHeight: 21000,
      submitterPubkey: key,
      submitterClass: cls,
    );

void main() {
  group('set_submitter_key preimage (hand-derived golden)', () {
    test('approve as Device', () {
      expect(_hex(_msg(key: _key, cls: SubmitterClass.device)), _setDeviceHex);
    });

    test('approve as Relay differs only in the class byte', () {
      expect(_hex(_msg(key: _key, cls: SubmitterClass.relay)), _setRelayHex);
    });

    test('clear', () {
      expect(_hex(_msg()), _clearHex);
    });

    test('base bytes are the plain owner action with discriminant 5', () {
      final plain = stationOwnerActionMessage(
        chainId: _chain,
        networkId: _network,
        stationId: _station,
        ownerAddress: _a1,
        action: StationOwnerAction.reportStolen,
        actionNonce: 7,
        expiresAtHeight: 21000,
      );
      final clear = _msg();
      expect(clear.length, plain.length + 1);
      expect(clear[plain.length - 17], stationSetSubmitterKeyDiscriminant);
      expect(stationSetSubmitterKeyDiscriminant, 5);
    });

    test('frozen class discriminants and wire names', () {
      expect(SubmitterClass.device.discriminant, 1);
      expect(SubmitterClass.relay.discriminant, 2);
      expect(SubmitterClass.device.wireName, 'device');
      expect(SubmitterClass.relay.wireName, 'relay');
      expect(SubmitterClass.fromWire('device'), SubmitterClass.device);
      expect(SubmitterClass.fromWire('Device'), isNull);
      expect(stationSetSubmitterKeyWireName, 'set_submitter_key');
    });

    test('refuses incomplete or non-canonical submitter fields', () {
      expect(() => _msg(key: _key), throwsArgumentError);
      expect(() => _msg(cls: SubmitterClass.device), throwsArgumentError);
      expect(
        () => _msg(key: _key.toUpperCase(), cls: SubmitterClass.device),
        throwsArgumentError,
      );
      expect(
        () => _msg(key: 'ab' * 31, cls: SubmitterClass.device),
        throwsArgumentError,
      );
      expect(
        () => _msg(key: 'zz' * 32, cls: SubmitterClass.device),
        throwsArgumentError,
      );
    });
  });

  group('signing with a real wallet key', () {
    test('signs approve and clear; key and class are bound', () async {
      final w = await ownerWallet(ownerSeedA);
      final signed = await w.session.signSetSubmitterKey(
        submitterPubkey: _key,
        submitterClass: SubmitterClass.device,
        actionNonce: 4,
        expiresAtHeight: 6000,
      );
      List<int> expected({String? key, SubmitterClass? cls}) =>
          stationOwnerSetSubmitterMessage(
            chainId: ownerDomain.chainId,
            networkId: ownerDomain.networkId,
            stationId: w.session.stationId,
            ownerAddress: w.address,
            actionNonce: 4,
            expiresAtHeight: 6000,
            submitterPubkey: key,
            submitterClass: cls,
          );
      expect(signed.publicKeyHex, w.pubkey);
      expect(
        await verifyEd25519(
          signed.publicKeyHex,
          signed.signatureHex,
          expected(key: _key, cls: SubmitterClass.device),
        ),
        isTrue,
      );
      // Swapping the class or key after signing breaks the signature.
      expect(
        await verifyEd25519(
          signed.publicKeyHex,
          signed.signatureHex,
          expected(key: _key, cls: SubmitterClass.relay),
        ),
        isFalse,
      );
      expect(
        await verifyEd25519(
          signed.publicKeyHex,
          signed.signatureHex,
          expected(key: 'c4' * 32, cls: SubmitterClass.device),
        ),
        isFalse,
      );
      expect(
        await verifyEd25519(
          signed.publicKeyHex,
          signed.signatureHex,
          expected(),
        ),
        isFalse,
      );

      final cleared = await w.session.signSetSubmitterKey(
        submitterPubkey: null,
        submitterClass: null,
        actionNonce: 4,
        expiresAtHeight: 6000,
      );
      expect(
        await verifyEd25519(
          cleared.publicKeyHex,
          cleared.signatureHex,
          expected(),
        ),
        isTrue,
      );
      w.session.close();
    });
  });

  // Cross-check against the frontend's independently hand-derived vectors
  // (wrfcoin/frontend worktree wt-fe-relay-submitter,
  // src/services/walletCrypto/__tests__/s10-submitter-key-888-vectors.json):
  // same core4 46e9de9 code, chain 888, owner seed [7;32], submitter seed
  // [9;32]. The bytes must be identical, and the frontend's signatures must
  // verify over the bytes this app builds.
  group('frontend 888 vectors (independent derivation)', () {
    const owner = '0x791026e25cc1ba461167ffb5c6dc095c284bd92c';
    const ownerPub =
        'ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c';
    final cases = <({String name, String? key, SubmitterClass? cls, String preimage, String sig})>[
      (
        name: 'relay',
        key: 'fd1724385aa0c75b64fb78cd602fa1d991fdebf76b13c58ed702eac835e9f618',
        cls: SubmitterClass.relay,
        preimage:
            '777266636f696e5f73746174696f6e5f6f776e65725f616374696f6e5f763103'
            '00000038383807000000746573746e65741000000073746174696f6e2d733130'
            '2d746573742a0000003078373931303236653235636331626134363131363766'
            '6662356336646330393563323834626439326305070000000000000008520000'
            '0000000001400000006664313732343338356161306337356236346662373863'
            '6436303266613164393931666465626637366231336335386564373032656163'
            '38333565396636313802',
        sig:
            '51430982727723bdedb8417ba4d3c9d384488b2d1b5ed5644f9f436ea9405390'
            'a70588eae83376af73aae5abcbe99d1ded309012f1f597fcb243983cdd1adc01',
      ),
      (
        name: 'device',
        key: 'fd1724385aa0c75b64fb78cd602fa1d991fdebf76b13c58ed702eac835e9f618',
        cls: SubmitterClass.device,
        preimage:
            '777266636f696e5f73746174696f6e5f6f776e65725f616374696f6e5f763103'
            '00000038383807000000746573746e65741000000073746174696f6e2d733130'
            '2d746573742a0000003078373931303236653235636331626134363131363766'
            '6662356336646330393563323834626439326305070000000000000008520000'
            '0000000001400000006664313732343338356161306337356236346662373863'
            '6436303266613164393931666465626637366231336335386564373032656163'
            '38333565396636313801',
        sig:
            '125bb44eb81b2d0784446a25fc7f573acac050233826031b305bbbeb3ee4f7a4'
            '1057e4458d5ef5d9db0ed74f3cc9bd21cf1873c63e43cdbfbedb3c9e4cd37503',
      ),
      (
        name: 'clear',
        key: null,
        cls: null,
        preimage:
            '777266636f696e5f73746174696f6e5f6f776e65725f616374696f6e5f763103'
            '00000038383807000000746573746e65741000000073746174696f6e2d733130'
            '2d746573742a0000003078373931303236653235636331626134363131363766'
            '6662356336646330393563323834626439326305070000000000000008520000'
            '0000000000',
        sig:
            'd7899b9be909124e958a660542c6938b3ef3b8d216e229a64095775700b2879a'
            '386cf8a5e3b77211920e8e7afa25eeb600f367b73b83914827b33db34a14af0a',
      ),
    ];
    for (final c in cases) {
      test('identical bytes: ${c.name}', () async {
        final msg = stationOwnerSetSubmitterMessage(
          chainId: '888',
          networkId: 'testnet',
          stationId: 'station-s10-test',
          ownerAddress: owner,
          actionNonce: 7,
          expiresAtHeight: 21000,
          submitterPubkey: c.key,
          submitterClass: c.cls,
        );
        expect(_hex(msg), c.preimage);
        expect(await verifyEd25519(ownerPub, c.sig, msg), isTrue);
      });
    }
  });
}
