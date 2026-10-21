import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_exchange.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_service.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../../station_owner_fixtures.dart';

void main() {
  group('OwnerLedger', () {
    test('parses the owner-ledger contract', () {
      final l = OwnerLedger.fromJson(
        ledgerJson(
          frozen: {'since_height': 55},
          pending: {
            'from_owner_address': 'wrfa',
            'to_owner_address': 'wrfb',
            'recovery_nonce': 3,
            'filed_at_height': 900,
            'executable_at_height': 34900,
          },
        ),
      );
      expect(l.ownerNonce, 3);
      expect(l.frozenSinceHeight, 55);
      expect(l.pendingRecovery!.executableAtHeight, 34900);
      expect(l.consentActive, isTrue);
      expect(l.observedAtHeight, 1000);
    });

    test('malformed bodies throw instead of defaulting', () {
      final bad = <Object?>[
        <String, dynamic>{},
        'x',
        ledgerJson()..remove('ownerNonce'),
        (ledgerJson()..['ownerNonce'] = 'x'),
        ledgerJson()..remove('observedAtHeight'),
        ledgerJson()..remove('features'),
        ledgerJson()..remove('ownerCommitment'),
      ];
      for (final b in bad) {
        expect(
          () => OwnerLedger.fromJson(b),
          throwsFormatException,
          reason: '$b',
        );
      }
    });
  });

  group('DioStationOwnerApi', () {
    DioStationOwnerApi apiReturning(int status, Object body) {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            final res = Response(
              requestOptions: o,
              statusCode: status,
              data: body,
            );
            status >= 400
                ? h.reject(
                    DioException(
                      requestOptions: o,
                      response: res,
                      type: DioExceptionType.badResponse,
                    ),
                  )
                : h.resolve(res);
          },
        ),
      );
      return DioStationOwnerApi(dio);
    }

    const payload = SignedOwnerPayload(
      stationId: 'st',
      kind: 'transfer',
      payload: '{}',
    );

    test('maps every OWNER_TX_* code and never trusts the message', () async {
      final codes = <String, StationOwnerRefusal>{
        'OWNER_TX_NONCE_MISMATCH': StationOwnerRefusal.nonceMismatch,
        'OWNER_TX_STATION_FROZEN': StationOwnerRefusal.stationFrozen,
        'OWNER_TX_FEATURE_NOT_ACTIVE': StationOwnerRefusal.featureNotActive,
        'OWNER_TX_EXPIRED': StationOwnerRefusal.expired,
        'OWNER_TX_NOT_REGISTERED_OWNER': StationOwnerRefusal.notRegisteredOwner,
        'OWNER_TX_BAD_COUNTERSIGNATURE':
            StationOwnerRefusal.badCountersignature,
        'OWNER_TX_NO_PENDING_RECOVERY': StationOwnerRefusal.noPendingRecovery,
        'OWNER_TX_NOTICE_WINDOW_ELAPSED':
            StationOwnerRefusal.noticeWindowElapsed,
        'OWNER_TX_STALE_TIMESTAMP': StationOwnerRefusal.staleTimestamp,
        'OWNER_TX_ID_MISMATCH': StationOwnerRefusal.idMismatch,
        'CHAIN_IDENTITY_MISMATCH': StationOwnerRefusal.chainIdentityMismatch,
        'MEMPOOL_REJECTED': StationOwnerRefusal.mempoolRejected,
      };
      for (final e in codes.entries) {
        final api = apiReturning(422, {
          'ok': false,
          'error': {'code': e.key, 'message': 'Success! all good'},
        });
        try {
          await api.submit(payload);
          fail('expected failure for ${e.key}');
        } on StationOwnerException catch (x) {
          expect(x.refusal, e.value, reason: e.key);
          expect(x.code, e.key);
        }
      }
    });

    test(
      'unknown codes and non-JSON errors are unknown, not success',
      () async {
        for (final body in <Object>[
          {
            'error': {'code': 'SOMETHING_NEW'},
          },
          'oops',
          <String, dynamic>{},
        ]) {
          try {
            await apiReturning(422, body).submit(payload);
            fail('expected failure');
          } on StationOwnerException catch (x) {
            expect(x.refusal, StationOwnerRefusal.unknown);
          }
        }
      },
    );

    test(
      '503 is unavailable, 401/403/429 are auth/rate, never success',
      () async {
        final cases = <int, StationOwnerRefusal>{
          503: StationOwnerRefusal.unavailable,
          401: StationOwnerRefusal.loginRequired,
          403: StationOwnerRefusal.notTheSigner,
          429: StationOwnerRefusal.rateLimited,
        };
        for (final e in cases.entries) {
          for (final call in <Future<Object?> Function(DioStationOwnerApi)>[
            (a) => a.submit(payload),
            (a) => a.readLedger('st'),
          ]) {
            try {
              await call(apiReturning(e.key, <String, dynamic>{}));
              fail('expected failure for ${e.key}');
            } on StationOwnerException catch (x) {
              expect(x.refusal, e.value, reason: '${e.key}');
            }
          }
        }
      },
    );

    test('201 is only "accepted", carrying ids', () async {
      final r = await apiReturning(201, {
        'status': 'accepted_pending_confirmation',
        'applied': false,
        'transactionIds': ['ab'],
        'admissionHeight': 12,
      }).submit(payload);
      expect(r.transactionIds, ['ab']);
      expect(r.admissionHeight, 12);
    });

    test('a 201 that is not the pending shape is uncertain', () async {
      try {
        await apiReturning(201, <String, dynamic>{}).submit(payload);
        fail('expected failure');
      } on StationOwnerException catch (x) {
        expect(x.refusal, StationOwnerRefusal.uncertain);
      }
    });

    test('readLedger parses and rejects malformed bodies', () async {
      expect(
        (await apiReturning(200, ledgerJson()).readLedger('st')).ownerNonce,
        3,
      );
      await expectLater(
        apiReturning(200, <String, dynamic>{}).readLedger('st'),
        throwsA(isA<StationOwnerException>()),
      );
    });
  });

  group('exchange codec', () {
    test('offer round-trips and carries no key material', () async {
      final a = await ownerWallet(ownerSeedA);
      final b = await ownerWallet(ownerSeedB);
      final offer = await a.session.signTransferAsSender(
        toOwnerAddress: b.address,
        toOwnerPubkey: b.pubkey,
        transferNonce: 3,
        expiresAtHeight: 6000,
      );
      final text = TransferOffer.fromSigned(offer).encode();
      expect(text.contains(ownerSeedA), isFalse);
      expect(text.contains(ownerSeedB), isFalse);
      final back = TransferOffer.decode(text);
      expect(back.body.stationId, offer.body.stationId);
      expect(back.body.toOwnerAddress, b.address);
      expect(back.fromOwnerPubkey, a.pubkey);
      expect(back.fromOwnerSignature, offer.signed.signatureHex);
    });

    test('decode is strict: junk, wrong kind, extras and secrets', () {
      Map<String, dynamic> good() => {
        'v': 1,
        'kind': 'station_transfer_offer_v1',
        'chain_id': 'c-1',
        'network_id': 'n-1',
        'station_id': 'st',
        'from_owner_address': '0xa',
        'from_owner_pubkey': 'b' * 64,
        'to_owner_address': '0xb',
        'to_owner_pubkey': 'c' * 64,
        'transfer_nonce': 1,
        'expires_at_height': 10,
        'from_owner_signature': 'd' * 128,
      };
      expect(
        () => TransferOffer.decode(packExchangeText('offer', good())),
        returnsNormally,
      );
      String pack(Map<String, dynamic> m) => packExchangeText('offer', m);
      final goodText = pack(good());
      final bads = <String>[
        'not json',
        '[]',
        '',
        pack(good()..['kind'] = 'other'),
        pack(good()..['v'] = 2),
        pack(good()..remove('from_owner_signature')),
        pack(good()..['transfer_nonce'] = '1'),
        pack(good()..['private_key'] = 'x'),
        pack(good()..['seed'] = 'x'),
        pack(good()..['mnemonic'] = 'x'),
        pack(good()..['unexpected'] = 1),
        pack(good()..['from_owner_pubkey'] = 'zz'),
        pack(good()..['from_owner_signature'] = 'dd'),
        // framing: truncated, mangled checksum, wrong prefix, wrong kind
        goodText.substring(0, goodText.length - 20),
        goodText.substring(0, goodText.length - 1),
        '${goodText.substring(0, goodText.length - 1)}0',
        goodText.replaceFirst('WRFOWN1', 'WRFOWN2'),
        goodText.replaceFirst('.offer.', '.receive.'),
        '${goodText.substring(0, 40)}A${goodText.substring(41)}',
        packExchangeText('receive', good()),
      ];
      for (final b in bads) {
        expect(() => TransferOffer.decode(b), throwsFormatException, reason: b);
      }
    });

    test('text is self-describing and tolerates wrapped pastes', () async {
      final b = await ownerWallet(ownerSeedB);
      final text = ReceiveCode(address: b.address, pubkey: b.pubkey).encode();
      expect(text.startsWith('WRFOWN1.receive.'), isTrue);
      final wrapped =
          '  ${text.substring(0, 30)}\n${text.substring(30, 90)}\r\n${text.substring(90)}  ';
      expect(ReceiveCode.decode(wrapped).address, b.address);
    });

    test('receive code round-trips and is strict', () async {
      final b = await ownerWallet(ownerSeedB);
      final text = ReceiveCode(address: b.address, pubkey: b.pubkey).encode();
      final back = ReceiveCode.decode(text);
      expect(back.address, b.address);
      expect(back.pubkey, b.pubkey);
      expect(
        () => ReceiveCode.decode(
          packExchangeText('receive', {
            'v': 1,
            'kind': 'station_receive_code_v1',
            'address': b.address,
            'pubkey': b.pubkey,
            'seed': 'x',
          }),
        ),
        throwsFormatException,
      );
      expect(() => ReceiveCode.decode('nope'), throwsFormatException);
      expect(
        () => ReceiveCode.decode(
          ReceiveCode(address: b.address, pubkey: 'a' * 64).encode(),
        ),
        throwsFormatException,
        reason: 'pubkey must derive to the address',
      );
    });

    test('payload JSON omits unset signatures and orders by contract', () {
      final json = transferPayloadJson(
        TransferOffer(
          body: StationTransferBody(
            chainId: 'c-1',
            networkId: 'n-1',
            stationId: 'st',
            fromOwnerAddress: '0xa',
            toOwnerAddress: '0xb',
            toOwnerPubkey: 'c' * 64,
            transferNonce: 1,
            expiresAtHeight: 10,
          ),
          fromOwnerPubkey: 'b' * 64,
          fromOwnerSignature: 'd' * 128,
        ),
        toOwnerSignature: null,
      );
      final m = jsonDecode(json) as Map<String, dynamic>;
      expect(m['tx_kind'], 'station_owner_transfer_v1');
      expect(m.containsKey('to_owner_signature'), isFalse);
      expect(m['from_owner_signature'], 'd' * 128);
      expect(m['transfer_nonce'], 1);
    });
  });

  group('StationOwnerService', () {
    Future<
      ({
        OwnerWallet a,
        OwnerWallet b,
        FakeOwnerApi api,
        StationOwnerService sender,
        StationOwnerService receiver,
      })
    >
    setup({Map<String, dynamic>? ledger}) async {
      final a = await ownerWallet(ownerSeedA);
      final b = await ownerWallet(ownerSeedB);
      final api = FakeOwnerApi(
        ledger ?? ledgerJson(stationId: a.session.stationId, owner: a.address),
      );
      return (
        a: a,
        b: b,
        api: api,
        sender: StationOwnerService(
          api: api,
          openSession: () async => a.session,
        ),
        receiver: StationOwnerService(
          api: api,
          openSession: () async => (await ownerWallet(ownerSeedB)).session,
        ),
      );
    }

    test('startTransfer uses the ledger nonce and tip+5000 expiry', () async {
      final t = await setup();
      final r = await t.sender.startTransfer(
        ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
      );
      expect(r.offer.body.transferNonce, 3);
      expect(r.offer.body.expiresAtHeight, 1000 + 5000);
      expect(r.offer.body.fromOwnerAddress, t.a.address);
      expect(
        await verifyEd25519(
          r.offer.fromOwnerPubkey,
          r.offer.fromOwnerSignature,
          stationOwnerTransferMessage(r.offer.body),
        ),
        isTrue,
      );
      expect(t.api.submitted, isEmpty, reason: 'sender never submits');
    });

    test('startTransfer refuses when the ledger forbids it', () async {
      final a = await ownerWallet(ownerSeedA);
      final b = await ownerWallet(ownerSeedB);
      final cases = <String, Map<String, dynamic>>{
        'consent inactive': ledgerJson(
          stationId: a.session.stationId,
          owner: a.address,
          consent: false,
        ),
        'frozen': ledgerJson(
          stationId: a.session.stationId,
          owner: a.address,
          frozen: {'since_height': 5},
        ),
        'not the owner': ledgerJson(
          stationId: a.session.stationId,
          owner: b.address,
        ),
      };
      for (final e in cases.entries) {
        final api = FakeOwnerApi(e.value);
        final svc = StationOwnerService(
          api: api,
          openSession: () async => a.session,
        );
        await expectLater(
          svc.startTransfer(ReceiveCode(address: b.address, pubkey: b.pubkey)),
          throwsA(isA<StationOwnerBlocked>()),
          reason: e.key,
        );
      }
    });

    test('ledger read failure blocks signing (no stale nonce)', () async {
      final t = await setup();
      t.api.readError = const StationOwnerException(
        StationOwnerRefusal.unknown,
      );
      await expectLater(
        t.sender.startTransfer(
          ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
        ),
        throwsA(isA<StationOwnerException>()),
      );
    });

    test('accept: verifies, countersigns the same body, submits both sigs', () async {
      final t = await setup();
      final r = await t.sender.startTransfer(
        ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
      );
      final flow = await t.receiver.beginAccept(r.offer.encode());
      expect(flow.offer.body.toOwnerAddress, t.b.address);
      final sub = await flow.accept();
      expect(t.api.submitted, hasLength(1));
      final m =
          jsonDecode(t.api.submitted.single.payload) as Map<String, dynamic>;
      expect(m['tx_kind'], 'station_owner_transfer_v1');
      // the posted text is exactly the payload text built from what was signed
      expect(
        t.api.submitted.single.payload,
        transferPayloadJson(
          r.offer,
          toOwnerSignature: m['to_owner_signature'] as String,
        ),
      );
      expect(m['from_owner_signature'], r.offer.fromOwnerSignature);
      expect(m['transfer_nonce'], 3);
      expect(
        await verifyEd25519(
          t.b.pubkey,
          m['to_owner_signature'] as String,
          stationOwnerTransferAcceptMessage(r.offer.body),
        ),
        isTrue,
      );
      expect(sub.baselineNonce, 3);
      flow.close();
    });

    Future<StationOwnerService> receiverFor(
      OwnerWallet b,
      FakeOwnerApi api,
    ) async => StationOwnerService(
      api: api,
      openSession: () async => (await ownerWallet(ownerSeedB)).session,
    );

    test('accept refuses every mismatch before signing', () async {
      final t = await setup();
      final good = (await t.sender.startTransfer(
        ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
      )).offer;

      TransferOffer tweak({
        String? chain,
        String? to,
        String? toPub,
        int? nonce,
        int? expires,
        String? sig,
        String? fromPub,
      }) => TransferOffer(
        body: StationTransferBody(
          chainId: chain ?? good.body.chainId,
          networkId: good.body.networkId,
          stationId: good.body.stationId,
          fromOwnerAddress: good.body.fromOwnerAddress,
          toOwnerAddress: to ?? good.body.toOwnerAddress,
          toOwnerPubkey: toPub ?? good.body.toOwnerPubkey,
          transferNonce: nonce ?? good.body.transferNonce,
          expiresAtHeight: expires ?? good.body.expiresAtHeight,
        ),
        fromOwnerPubkey: fromPub ?? good.fromOwnerPubkey,
        fromOwnerSignature: sig ?? good.fromOwnerSignature,
      );

      final cases = <String, (TransferOffer, OfferProblem)>{
        'foreign chain': (tweak(chain: 'other'), OfferProblem.wrongChain),
        'not for me': (
          tweak(to: t.a.address.replaceFirst('0x', 'wrf')),
          OfferProblem.notForThisWallet,
        ),
        'wrong key': (tweak(toPub: t.a.pubkey), OfferProblem.notForThisWallet),
        'bad signature': (tweak(sig: '0' * 128), OfferProblem.badSignature),
        'tampered nonce': (tweak(nonce: 4), OfferProblem.badSignature),
        'sender key unbound': (
          tweak(fromPub: t.b.pubkey),
          OfferProblem.senderKeyNotBound,
        ),
      };
      for (final e in cases.entries) {
        final svc = await receiverFor(t.b, t.api);
        await expectLater(
          svc.beginAccept(e.value.$1.encode()),
          throwsA(
            isA<OfferRejected>().having(
              (x) => x.problem,
              'problem',
              e.value.$2,
            ),
          ),
          reason: e.key,
        );
      }
      expect(t.api.submitted, isEmpty);
    });

    test('accept refuses stale ledger state and expiry', () async {
      final t = await setup();
      final offer = (await t.sender.startTransfer(
        ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
      )).offer;
      final id = t.a.session.stationId;

      final ledgers = <String, (Map<String, dynamic>, OfferProblem)>{
        'nonce moved': (
          ledgerJson(stationId: id, owner: t.a.address, nonce: 4),
          OfferProblem.nonceMismatch,
        ),
        'expired': (
          ledgerJson(stationId: id, owner: t.a.address, observed: 6000),
          OfferProblem.expired,
        ),
        'owner changed': (
          ledgerJson(stationId: id, owner: t.b.address),
          OfferProblem.senderIsNotOwner,
        ),
        'frozen': (
          ledgerJson(
            stationId: id,
            owner: t.a.address,
            frozen: {'since_height': 1},
          ),
          OfferProblem.stationFrozen,
        ),
        'consent inactive': (
          ledgerJson(stationId: id, owner: t.a.address, consent: false),
          OfferProblem.featureNotActive,
        ),
      };
      for (final e in ledgers.entries) {
        t.api.ledgerBody = e.value.$1;
        await expectLater(
          (await receiverFor(t.b, t.api)).beginAccept(offer.encode()),
          throwsA(
            isA<OfferRejected>().having(
              (x) => x.problem,
              'problem',
              e.value.$2,
            ),
          ),
          reason: e.key,
        );
      }
    });

    test('accept re-reads the ledger right before countersigning', () async {
      final t = await setup();
      final offer = (await t.sender.startTransfer(
        ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
      )).offer;
      final id = t.a.session.stationId;
      final moved = <String, Map<String, dynamic>>{
        'nonce moved': ledgerJson(stationId: id, owner: t.a.address, nonce: 4),
        'owner changed': ledgerJson(stationId: id, owner: t.b.address),
        'frozen since review': ledgerJson(
          stationId: id,
          owner: t.a.address,
          frozen: {'since_height': 1},
        ),
        'expired since review': ledgerJson(
          stationId: id,
          owner: t.a.address,
          observed: 6000,
        ),
      };
      for (final e in moved.entries) {
        t.api.ledgerBody = ledgerJson(stationId: id, owner: t.a.address);
        final flow = await t.receiver.beginAccept(offer.encode());
        // minutes pass: the ledger moves under the open review screen
        t.api.ledgerBody = e.value;
        await expectLater(
          flow.accept(),
          throwsA(isA<OfferRejected>()),
          reason: e.key,
        );
        expect(t.api.submitted, isEmpty, reason: '${e.key}: nothing sent');
        flow.close();
      }
    });

    test('a read failure at the final check blocks the countersign', () async {
      final t = await setup();
      final offer = (await t.sender.startTransfer(
        ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
      )).offer;
      final flow = await t.receiver.beginAccept(offer.encode());
      t.api.readError = const StationOwnerException(
        StationOwnerRefusal.unavailable,
      );
      await expectLater(flow.accept(), throwsA(isA<StationOwnerException>()));
      expect(t.api.submitted, isEmpty);
      flow.close();
    });

    test(
      'a 201 is pending, never applied; confirmed only on ledger change',
      () async {
        final t = await setup();
        final offer = (await t.sender.startTransfer(
          ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
        )).offer;
        final flow = await t.receiver.beginAccept(offer.encode());
        final sub = await flow.accept();

        // unchanged ledger after a 201: still pending
        expect(
          await t.receiver.checkTransferApplied(sub),
          TransferStatus.pendingConfirmation,
        );
        // nonce advanced but owner not yet the new owner: still pending
        t.api.ledgerBody = ledgerJson(
          stationId: sub.stationId,
          owner: t.a.address,
          nonce: 4,
        );
        expect(
          await t.receiver.checkTransferApplied(sub),
          TransferStatus.pendingConfirmation,
        );
        // owner moved to me and nonce advanced
        t.api.ledgerBody = ledgerJson(
          stationId: sub.stationId,
          owner: t.b.address,
          nonce: 4,
        );
        expect(
          await t.receiver.checkTransferApplied(sub),
          TransferStatus.confirmed,
        );
        // a read failure never reads as confirmed
        t.api.readError = const StationOwnerException(
          StationOwnerRefusal.unknown,
        );
        expect(
          await t.receiver.checkTransferApplied(sub),
          TransferStatus.unknown,
        );
      },
    );

    test('submit refusals surface typed and sign nothing twice', () async {
      final t = await setup();
      final offer = (await t.sender.startTransfer(
        ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
      )).offer;
      t.api.submitError = const StationOwnerException(
        StationOwnerRefusal.nonceMismatch,
        code: 'OWNER_TX_NONCE_MISMATCH',
      );
      final flow = await t.receiver.beginAccept(offer.encode());
      await expectLater(
        flow.accept(),
        throwsA(
          isA<StationOwnerException>().having(
            (e) => e.refusal,
            'refusal',
            StationOwnerRefusal.nonceMismatch,
          ),
        ),
      );
      expect(t.api.submitted, isEmpty);
    });

    test('biometric refusal cancels without signing', () async {
      final t = await setup();
      final svc = StationOwnerService(
        api: t.api,
        openSession: () async => null,
      );
      await expectLater(
        svc.startTransfer(
          ReceiveCode(address: t.b.address, pubkey: t.b.pubkey),
        ),
        throwsA(isA<StationOwnerCancelled>()),
      );
    });
  });
}
