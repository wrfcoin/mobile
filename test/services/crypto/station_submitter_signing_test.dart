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
}
