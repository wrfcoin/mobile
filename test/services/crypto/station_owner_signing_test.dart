import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../../test_helpers/fakes.dart';

// Goldens: core4 #3433 head 1cdc45f2, shared-protocol/tests/fixtures/golden/
// signing_preimage_v2.json (copied via r23/station-owner-actions-spec.md §4).
// PROVISIONAL until #3433 merges. The fixture pubkeys are SYNTHETIC (they do
// not derive to the fixture addresses), so these pin preimage bytes and the
// fixture signature only; key binding is covered by the real-key tests below.
const _chain = 'wrfcoin-testnet';
const _network = 'testnet';
const _station = 'station-golden-3345';
const _actionStation = 'station-golden-3347';
final _a1 = 'wrf${'a1' * 20}';
final _b2 = 'wrf${'b2' * 20}';
final _c3 = 'wrf${'c3' * 20}';
final _b3Pub = 'b3' * 32;
final _c4Pub = 'c4' * 32;

const _transferHex =
    '777266636f696e5f73746174696f6e5f6f776e65725f7472616e736665725f76310f000000777266636f696e2d746573746e657407000000746573746e65741300000073746174696f6e2d676f6c64656e2d333334352b000000777266613161316131613161316131613161316131613161316131613161316131613161316131613161312b00000077726662326232623262326232623262326232623262326232623262326232623262326232623262326232400000006233623362336233623362336233623362336233623362336233623362336233623362336233623362336233623362336233623362336233623362336233623307000000000000000852000000000000';
const _transferSig =
    '1480fdcfc703670b8bc245a4e6632f52b4ec27176ecc7c3a37d1cc73316abc1dcbdd2e8cccbdbdc1a749a20848cda4d2607a9e2accdfdb7817d2ba49e04d250b';
const _transferPub =
    'd41ec1ff41c478b26265a22ba373af3186af2ce5bc3f02a7aed189609386a0a5';

const _acceptHex =
    '777266636f696e5f73746174696f6e5f6f776e65725f7472616e736665725f6163636570745f76310f000000777266636f696e2d746573746e657407000000746573746e65741300000073746174696f6e2d676f6c64656e2d333334352b000000777266613161316131613161316131613161316131613161316131613161316131613161316131613161312b00000077726662326232623262326232623262326232623262326232623262326232623262326232623262326232400000006233623362336233623362336233623362336233623362336233623362336233623362336233623362336233623362336233623362336233623362336233623307000000000000000852000000000000';
const _acceptSig =
    '0b0593b8ebc2f039c9a1598701ab7d6e0782c9b73cbb68f1a7432a1f62b15c75b54664961846b3cb3cb5b44e2e5a03a0a118a4394c0db037f5119fab0288060d';
const _acceptPub =
    '9affa0ecdacc69d9c7ef1a62d76ad073a1125bfd91dcab1053e3f263bfb42dc1';

const _raccHex =
    '777266636f696e5f73746174696f6e5f6f776e65725f7265636f766572795f6163636570745f76310f000000777266636f696e2d746573746e657407000000746573746e65741300000073746174696f6e2d676f6c64656e2d333334352b000000777266613161316131613161316131613161316131613161316131613161316131613161316131613161312b0000007772666333633363336333633363336333633363336333633363336333633363336333633363336333633340000000633463346334633463346334633463346334633463346334633463346334633463346334633463346334633463346334633463346334633463346334633463340700000000000000';
const _raccSig =
    'bbe7c6f68b76c7ad1ecd6c1009bf83fd9419934d32c65e414237532b2e16a62b9bf47eb52c9d5f28ec71dc1acbfdb967f7b5268b769f09ee0fe5667788503601';
const _raccPub =
    'b4fd59d80f6a56e05eabd4c7b214827243880ce266c477a957ea50abe501772a';

const _cancelHex =
    '777266636f696e5f73746174696f6e5f6f776e65725f7265636f766572795f63616e63656c5f76310f000000777266636f696e2d746573746e657407000000746573746e65741300000073746174696f6e2d676f6c64656e2d333334352b000000777266613161316131613161316131613161316131613161316131613161316131613161316131613161310700000000000000';
const _cancelSig =
    '13f2485f7bb928185d96fdbec200320ed7929108e4af9ad460b254c928c8d5288fbdc26cec154486259881ab44649166aa49965445fd4595ecac568f9a881008';
const _cancelPub =
    '2861ee36d1ca9ac267058d82f8d767de555512929c49de6fcfdab0992e8d69c0';

const _actionHex =
    '777266636f696e5f73746174696f6e5f6f776e65725f616374696f6e5f76310f000000777266636f696e2d746573746e657407000000746573746e65741300000073746174696f6e2d676f6c64656e2d333334372b000000777266613161316131613161316131613161316131613161316131613161316131613161316131613161310107000000000000000852000000000000';
const _actionSig =
    '4d5e65cffdd895bd709c8561da1d3d6fcdc6f7ba5c4179125279145120684615c32c3b20e59453c4b0df3113f4fbed1e620cab25bfe4ed441240700a16d3390b';
const _actionPub =
    'ec40ce8a6eff137053e3ad881f45f23b2f90b71c9d93836129b734d93887a57f';

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

StationTransferBody _transferBody({
  String? station,
  String? from,
  String? to,
  String? toPubkey,
  int nonce = 7,
  int expires = 21000,
  String chain = _chain,
  String network = _network,
}) => StationTransferBody(
  chainId: chain,
  networkId: network,
  stationId: station ?? _station,
  fromOwnerAddress: from ?? _a1,
  toOwnerAddress: to ?? _b2,
  toOwnerPubkey: toPubkey ?? _b3Pub,
  transferNonce: nonce,
  expiresAtHeight: expires,
);

StationRecoveryBody _recoveryBody({
  String? to,
  String? toPubkey,
  int nonce = 7,
}) => StationRecoveryBody(
  chainId: _chain,
  networkId: _network,
  stationId: _station,
  fromOwnerAddress: _a1,
  toOwnerAddress: to ?? _c3,
  toOwnerPubkey: toPubkey ?? _c4Pub,
  recoveryNonce: nonce,
);

const _seedA =
    '0707070707070707070707070707070707070707070707070707070707070707';
const _seedB =
    '0808080808080808080808080808080808080808080808080808080808080808';
const _domain = TransferSigningDomain(chainId: _chain, networkId: _network);

Future<({StationSigningSession session, String address})> _openFor(
  String seed,
) async {
  final signer = await Ed25519TransferSigner.fromSeedHex(seed);
  final address = chainAddressFromEd25519PublicKey(signer.publicKey);
  final km = KeyManager(
    biometric: BiometricService(client: FakeLocalAuthClient()),
    storage: InMemoryKeyValueStorage(),
  );
  await km.storeKeys(
    mnemonic: 'test words',
    privateKey: seed,
    address: address,
  );
  final session = (await StationSigningService(
    keyManager: km,
    domain: _domain,
    isForeground: () => true,
  ).openSession())!;
  return (session: session, address: address);
}

void main() {
  group('golden preimages (core4 #3433)', () {
    test('transfer (current owner)', () async {
      final msg = stationOwnerTransferMessage(_transferBody());
      expect(_hex(msg), _transferHex);
      expect(await _verify(_transferPub, _transferSig, msg), isTrue);
    });

    test('transfer-accept (new owner, same body, other tag)', () async {
      final msg = stationOwnerTransferAcceptMessage(_transferBody());
      expect(_hex(msg), _acceptHex);
      expect(await _verify(_acceptPub, _acceptSig, msg), isTrue);
      expect(_hex(msg), isNot(_transferHex));
    });

    test('recovery accept (new owner)', () async {
      final msg = stationOwnerRecoveryAcceptMessage(_recoveryBody());
      expect(_hex(msg), _raccHex);
      expect(await _verify(_raccPub, _raccSig, msg), isTrue);
    });

    test('recovery cancel (current owner, no expiry)', () async {
      final msg = stationOwnerRecoveryCancelMessage(
        chainId: _chain,
        networkId: _network,
        stationId: _station,
        ownerAddress: _a1,
        recoveryNonce: 7,
      );
      expect(_hex(msg), _cancelHex);
      expect(await _verify(_cancelPub, _cancelSig, msg), isTrue);
    });

    test('owner action report_stolen (discriminant 1)', () async {
      final msg = stationOwnerActionMessage(
        chainId: _chain,
        networkId: _network,
        stationId: _actionStation,
        ownerAddress: _a1,
        action: StationOwnerAction.reportStolen,
        actionNonce: 7,
        expiresAtHeight: 21000,
      );
      expect(_hex(msg), _actionHex);
      expect(await _verify(_actionPub, _actionSig, msg), isTrue);
    });

    test(
      'tampered inputs change the bytes and fail the fixture signature',
      () async {
        final tampers = <StationTransferBody>[
          _transferBody(station: 'station-golden-3346'),
          _transferBody(from: _c3),
          _transferBody(to: _c3),
          _transferBody(toPubkey: _c4Pub),
          _transferBody(nonce: 8),
          _transferBody(expires: 21001),
          _transferBody(chain: 'other'),
          _transferBody(network: 'mainnet'),
        ];
        for (final t in tampers) {
          final msg = stationOwnerTransferMessage(t);
          expect(_hex(msg), isNot(_transferHex));
          expect(await _verify(_transferPub, _transferSig, msg), isFalse);
        }
      },
    );

    test('action discriminants: frozen bytes 1..4, each differs', () {
      final seen = <String>{};
      final bytes = <int>[];
      for (final a in StationOwnerAction.values) {
        final m = stationOwnerActionMessage(
          chainId: _chain,
          networkId: _network,
          stationId: _actionStation,
          ownerAddress: _a1,
          action: a,
          actionNonce: 7,
          expiresAtHeight: 21000,
        );
        // discriminant sits just before nonce(8) + expiry(8) at the tail
        bytes.add(m[m.length - 17]);
        seen.add(_hex(m));
      }
      expect(StationOwnerAction.values.map((a) => a.discriminant).toList(), [
        1,
        2,
        3,
        4,
      ]);
      expect(bytes, [1, 2, 3, 4]);
      expect(StationOwnerAction.values.map((a) => a.wireName).toList(), [
        'report_stolen',
        'unfreeze',
        'deactivate',
        'reactivate',
      ]);
      expect(seen, hasLength(4));
    });

    // Goldens for discriminants 2-4: core4 theft-lane commit 8457a09a2
    // (shared-protocol/tests/fixtures/golden/signing_preimage_v2.json, seeds
    // 900136-900138). PROVISIONAL until that commit is pushed and merged.
    final goldens = <StationOwnerAction, (String, String, String)>{
      StationOwnerAction.unfreeze: (
        '777266636f696e5f73746174696f6e5f6f776e65725f616374696f6e5f76310f000000777266636f696e2d746573746e657407000000746573746e65741300000073746174696f6e2d676f6c64656e2d333334372b000000777266613161316131613161316131613161316131613161316131613161316131613161316131613161310207000000000000000852000000000000',
        'ada76cae250d62fe2192d4aeb9ed1131acc1e2c66ae8fd0e0d9d8414d28f5df27bbcd1a67cace0fab651f1e8dba04e78f4f188a1a5ff53e955eace3be3cf9c01',
        '651dc2c8b643b73922b8a205cb06f76d29fe6c326891af25f9e62b5ab0a3eb50',
      ),
      StationOwnerAction.deactivate: (
        '777266636f696e5f73746174696f6e5f6f776e65725f616374696f6e5f76310f000000777266636f696e2d746573746e657407000000746573746e65741300000073746174696f6e2d676f6c64656e2d333334372b000000777266613161316131613161316131613161316131613161316131613161316131613161316131613161310307000000000000000852000000000000',
        '98f6d3fc8a8479dab83617a0c6080f94cf735c3cab7262672831363733536055d435062d38d36aa67c55e4a858c262308afb8f28a63a8860e34492ede8dcd804',
        'ab963f94d5a1394e748fe8bcc8fec0f833a462ba34c9262f86459deaaa0d889d',
      ),
      StationOwnerAction.reactivate: (
        '777266636f696e5f73746174696f6e5f6f776e65725f616374696f6e5f76310f000000777266636f696e2d746573746e657407000000746573746e65741300000073746174696f6e2d676f6c64656e2d333334372b000000777266613161316131613161316131613161316131613161316131613161316131613161316131613161310407000000000000000852000000000000',
        '696066772b13f67fe560079930a16b8c58b49b7100eea00f0508fb4fa34cbca93cc5b771381acc05b460d0691431a4968ed0bb30a6e6322a13b5bb3e31b2b80f',
        'da3b59ac68b67e9318ba5b7eb02e5977baa3e8ca677852b5d1e87a4a4a89f1ff',
      ),
    };
    for (final e in goldens.entries) {
      test('golden for ${e.key.wireName}', () async {
        final msg = stationOwnerActionMessage(
          chainId: _chain,
          networkId: _network,
          stationId: _actionStation,
          ownerAddress: _a1,
          action: e.key,
          actionNonce: 7,
          expiresAtHeight: 21000,
        );
        expect(_hex(msg), e.value.$1);
        expect(await _verify(e.value.$3, e.value.$2, msg), isTrue);
        // the signed discriminant cannot be replayed as another action
        for (final other in StationOwnerAction.values.where(
          (x) => x != e.key,
        )) {
          final swapped = stationOwnerActionMessage(
            chainId: _chain,
            networkId: _network,
            stationId: _actionStation,
            ownerAddress: _a1,
            action: other,
            actionNonce: 7,
            expiresAtHeight: 21000,
          );
          expect(await _verify(e.value.$3, e.value.$2, swapped), isFalse);
        }
      });
    }

    test('rejects malformed fields', () {
      expect(
        () => stationOwnerTransferMessage(_transferBody(station: '')),
        throwsArgumentError,
      );
      expect(
        () => stationOwnerTransferMessage(_transferBody(station: 'a b')),
        throwsArgumentError,
      );
      expect(
        () => stationOwnerTransferMessage(_transferBody(nonce: -1)),
        throwsArgumentError,
      );
      expect(
        () => stationOwnerTransferMessage(_transferBody(from: _b2, to: _b2)),
        throwsArgumentError,
      );
    });

    test('signs the address string exactly as written (0x vs wrf differ)', () {
      final a = stationOwnerRecoveryCancelMessage(
        chainId: _chain,
        networkId: _network,
        stationId: _station,
        ownerAddress: 'wrf${'ab' * 20}',
        recoveryNonce: 1,
      );
      final b = stationOwnerRecoveryCancelMessage(
        chainId: _chain,
        networkId: _network,
        stationId: _station,
        ownerAddress: '0x${'ab' * 20}',
        recoveryNonce: 1,
      );
      expect(_hex(a), isNot(_hex(b)));
    });
  });

  group('signing with a real derived wallet key', () {
    test(
      'action: signs, verifies against the key that derives the address',
      () async {
        final o = await _openFor(_seedA);
        final signed = await o.session.signOwnerAction(
          action: StationOwnerAction.reportStolen,
          actionNonce: 3,
          expiresAtHeight: 5000,
        );
        expect(
          chainAddressFromEd25519PublicKey(_unhex(signed.publicKeyHex)),
          o.address,
        );
        final expected = stationOwnerActionMessage(
          chainId: _chain,
          networkId: _network,
          stationId: o.session.stationId,
          ownerAddress: o.address,
          action: StationOwnerAction.reportStolen,
          actionNonce: 3,
          expiresAtHeight: 5000,
        );
        expect(_hex(signed.message), _hex(expected));
        expect(
          await _verify(signed.publicKeyHex, signed.signatureHex, expected),
          isTrue,
        );
      },
    );

    test('every action signs and verifies against the owner key', () async {
      final o = await _openFor(_seedA);
      for (final a in StationOwnerAction.values) {
        expect(a.shippable, isTrue, reason: a.wireName);
        final signed = await o.session.signOwnerAction(
          action: a,
          actionNonce: 1,
          expiresAtHeight: 5000,
        );
        final expected = stationOwnerActionMessage(
          chainId: _chain,
          networkId: _network,
          stationId: o.session.stationId,
          ownerAddress: o.address,
          action: a,
          actionNonce: 1,
          expiresAtHeight: 5000,
        );
        expect(
          await _verify(signed.publicKeyHex, signed.signatureHex, expected),
          isTrue,
          reason: a.wireName,
        );
      }
    });

    test(
      'transfer: sender signs, new owner countersigns the SAME body',
      () async {
        final sender = await _openFor(_seedA);
        final receiver = await _openFor(_seedB);

        final offer = await sender.session.signTransferAsSender(
          toOwnerAddress: receiver.address,
          toOwnerPubkey: receiver.session.publicKeyHex,
          transferNonce: 4,
          expiresAtHeight: 9000,
        );
        expect(offer.body.fromOwnerAddress, sender.address);
        expect(offer.body.stationId, sender.session.stationId);
        expect(
          await _verify(
            offer.signed.publicKeyHex,
            offer.signed.signatureHex,
            stationOwnerTransferMessage(offer.body),
          ),
          isTrue,
        );

        final accept = await receiver.session.countersignTransferAccept(
          offer.body,
        );
        expect(
          await _verify(
            accept.publicKeyHex,
            accept.signatureHex,
            stationOwnerTransferAcceptMessage(offer.body),
          ),
          isTrue,
        );
        // the accept signature must not verify as the sender's message
        expect(
          await _verify(
            accept.publicKeyHex,
            accept.signatureHex,
            stationOwnerTransferMessage(offer.body),
          ),
          isFalse,
        );
      },
    );

    test('countersign refuses a body that does not name this wallet', () async {
      final sender = await _openFor(_seedA);
      final receiver = await _openFor(_seedB);
      // names a different recipient address
      final wrongAddr = _transferBody(
        from: sender.address,
        to: sender.address.replaceFirst('0x', 'wrf'),
        toPubkey: receiver.session.publicKeyHex,
      );
      await expectLater(
        receiver.session.countersignTransferAccept(wrongAddr),
        throwsA(isA<StationSigningUnavailable>()),
      );
      // right address, wrong pubkey
      final wrongKey = _transferBody(
        from: sender.address,
        to: receiver.address,
        toPubkey: sender.session.publicKeyHex,
      );
      await expectLater(
        receiver.session.countersignTransferAccept(wrongKey),
        throwsA(isA<StationSigningUnavailable>()),
      );
      // foreign chain identity
      final foreign = _transferBody(
        from: sender.address,
        to: receiver.address,
        toPubkey: receiver.session.publicKeyHex,
        chain: 'some-other-chain',
      );
      await expectLater(
        receiver.session.countersignTransferAccept(foreign),
        throwsA(isA<StationSigningUnavailable>()),
      );
    });

    test(
      'recovery accept countersign and cancel sign with the wallet key',
      () async {
        final owner = await _openFor(_seedA);
        final claimant = await _openFor(_seedB);
        final body = StationRecoveryBody(
          chainId: _chain,
          networkId: _network,
          stationId: owner.session.stationId,
          fromOwnerAddress: owner.address,
          toOwnerAddress: claimant.address,
          toOwnerPubkey: claimant.session.publicKeyHex,
          recoveryNonce: 2,
        );
        final acc = await claimant.session.countersignRecoveryAccept(body);
        expect(
          await _verify(
            acc.publicKeyHex,
            acc.signatureHex,
            stationOwnerRecoveryAcceptMessage(body),
          ),
          isTrue,
        );
        final cancel = await owner.session.signRecoveryCancel(recoveryNonce: 2);
        expect(
          await _verify(
            cancel.publicKeyHex,
            cancel.signatureHex,
            stationOwnerRecoveryCancelMessage(
              chainId: _chain,
              networkId: _network,
              stationId: owner.session.stationId,
              ownerAddress: owner.address,
              recoveryNonce: 2,
            ),
          ),
          isTrue,
        );
      },
    );

    test('closed session cannot sign; nothing sensitive is logged', () async {
      final logs = <String?>[];
      final original = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m);
      try {
        final o = await _openFor(_seedA);
        final s = await o.session.signOwnerAction(
          action: StationOwnerAction.reportStolen,
          actionNonce: 0,
          expiresAtHeight: 5000,
        );
        o.session.close();
        await expectLater(
          o.session.signRecoveryCancel(recoveryNonce: 0),
          throwsStateError,
        );
        final joined = logs.join('\n');
        expect(joined.contains(_seedA), isFalse);
        expect(joined.contains(s.signatureHex), isFalse);
        expect(o.session.toString().contains(_seedA), isFalse);
      } finally {
        debugPrint = original;
      }
    });
  });
}
