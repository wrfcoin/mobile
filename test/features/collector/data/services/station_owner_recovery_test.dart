import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_exchange.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_service.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../../station_owner_fixtures.dart';

Map<String, dynamic> pending({
  required String from,
  required String to,
  int nonce = 3,
  int filed = 900,
  int executable = 34900,
}) => {
  'from_owner_address': from,
  'to_owner_address': to,
  'recovery_nonce': nonce,
  'filed_at_height': filed,
  'executable_at_height': executable,
};

void main() {
  group('recovery payloads', () {
    test('cancel and execute payload field sets', () {
      final cancel = jsonDecode(
        recoveryCancelPayloadJson(
          stationId: 'st',
          ownerAddress: '0xa',
          ownerPubkey: 'b' * 64,
          recoveryNonce: 3,
          ownerSignature: 'c' * 128,
        ),
      ) as Map<String, dynamic>;
      expect(cancel.keys.toList(), [
        'tx_kind',
        'station_id',
        'owner_address',
        'owner_pubkey',
        'recovery_nonce',
        'owner_signature',
      ]);
      expect(cancel['tx_kind'], 'station_owner_recovery_cancel_v1');
      final exec = jsonDecode(
        recoveryExecutePayloadJson(stationId: 'st', recoveryNonce: 3),
      ) as Map<String, dynamic>;
      expect(exec, {
        'tx_kind': 'station_owner_recovery_execute_v1',
        'station_id': 'st',
        'recovery_nonce': 3,
      });
    });
  });

  group('recovery exchange text', () {
    test('request and accept round-trip, strict and checksummed', () async {
      final a = await ownerWallet(ownerSeedA);
      final b = await ownerWallet(ownerSeedB);
      final req = RecoveryRequest(
        body: StationRecoveryBody(
          chainId: 'c-1',
          networkId: 'n-1',
          stationId: 'st',
          fromOwnerAddress: a.address,
          toOwnerAddress: b.address,
          toOwnerPubkey: b.pubkey,
          recoveryNonce: 3,
        ),
      );
      final text = req.encode();
      expect(text.startsWith('WRFOWN1.recovery.'), isTrue);
      final back = RecoveryRequest.decode(text);
      expect(back.body.toOwnerAddress, b.address);
      expect(back.body.recoveryNonce, 3);

      final acc = RecoveryAcceptText(
        body: req.body,
        toOwnerSignature: 'd' * 128,
      ).encode();
      expect(acc.startsWith('WRFOWN1.recovery-accept.'), isTrue);
      expect(RecoveryAcceptText.decode(acc).toOwnerSignature, 'd' * 128);

      for (final bad in <String>[
        'junk',
        text.substring(0, text.length - 5),
        text.replaceFirst('.recovery.', '.offer.'),
        acc, // wrong kind of code
        packExchangeText('recovery', {'v': 1, 'kind': 'x'}),
        packExchangeText('recovery', {
          'v': 1,
          'kind': 'station_recovery_request_v1',
          'seed': 'x',
        }),
      ]) {
        expect(
          () => RecoveryRequest.decode(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('cancel recovery (current owner)', () {
    Future<({OwnerWallet a, FakeOwnerApi api, StationOwnerService svc})> setup(
      Map<String, dynamic> Function(OwnerWallet a, OwnerWallet b) ledger,
    ) async {
      final a = await ownerWallet(ownerSeedA);
      final b = await ownerWallet(ownerSeedB);
      final api = FakeOwnerApi(ledger(a, b));
      return (
        a: a,
        api: api,
        svc: StationOwnerService(
          api: api,
          openSession: () async => (await ownerWallet(ownerSeedA)).session,
        ),
      );
    }

    Map<String, dynamic> pendingLedger(
      OwnerWallet a,
      OwnerWallet b, {
      int nonce = 3,
      int observed = 1000,
      bool consent = true,
      String? owner,
    }) => ledgerJson(
      stationId: a.session.stationId,
      owner: owner ?? a.address,
      nonce: nonce,
      observed: observed,
      consent: consent,
      pending: pending(from: a.address, to: b.address, nonce: nonce),
    );

    test(
      'signs the cancel with the pending recovery nonce and submits',
      () async {
        final t = await setup((a, b) => pendingLedger(a, b));
        final sub = await t.svc.cancelRecovery();
        final tx = t.api.submitted.single;
        expect(tx.kind, 'recovery_cancel');
        final m = jsonDecode(tx.payload) as Map<String, dynamic>;
        expect(m['recovery_nonce'], 3);
        expect(m['owner_address'], t.a.address);
        expect(
          await verifyEd25519(
            m['owner_pubkey'] as String,
            m['owner_signature'] as String,
            stationOwnerRecoveryCancelMessage(
              chainId: ownerDomain.chainId,
              networkId: ownerDomain.networkId,
              stationId: t.a.session.stationId,
              ownerAddress: t.a.address,
              recoveryNonce: 3,
            ),
          ),
          isTrue,
        );
        expect(sub.baselineNonce, 3);
      },
    );

    test('refuses before signing when it cannot work', () async {
      final cases =
          <String, Map<String, dynamic> Function(OwnerWallet, OwnerWallet)>{
            'no pending recovery': (a, b) =>
                ledgerJson(stationId: a.session.stationId, owner: a.address),
            'consent inactive': (a, b) => pendingLedger(a, b, consent: false),
            'not the owner': (a, b) => pendingLedger(a, b, owner: b.address),
            'window elapsed': (a, b) => pendingLedger(a, b, observed: 34899),
            'nonce does not match pending': (a, b) => ledgerJson(
              stationId: a.session.stationId,
              owner: a.address,
              nonce: 4,
              pending: pending(from: a.address, to: b.address, nonce: 3),
            ),
          };
      for (final e in cases.entries) {
        final t = await setup(e.value);
        await expectLater(
          t.svc.cancelRecovery(),
          throwsA(isA<StationOwnerBlocked>()),
          reason: e.key,
        );
        expect(t.api.submitted, isEmpty, reason: e.key);
      }
    });

    test(
      'cancelled only when the pending recovery is gone AND nonce advanced',
      () async {
        final t = await setup((a, b) => pendingLedger(a, b));
        final sub = await t.svc.cancelRecovery();
        final a = t.a;
        final b = await ownerWallet(ownerSeedB);
        expect(
          await t.svc.checkRecoveryCancelled(sub),
          TransferStatus.pendingConfirmation,
        );
        t.api.ledgerBody = ledgerJson(
          stationId: sub.stationId,
          owner: a.address,
          nonce: 4,
          pending: pending(from: a.address, to: b.address, nonce: 3),
        );
        expect(
          await t.svc.checkRecoveryCancelled(sub),
          TransferStatus.pendingConfirmation,
        );
        t.api.ledgerBody = ledgerJson(
          stationId: sub.stationId,
          owner: a.address,
          nonce: 4,
        );
        expect(
          await t.svc.checkRecoveryCancelled(sub),
          TransferStatus.confirmed,
        );
        t.api.readError = const StationOwnerException(
          StationOwnerRefusal.unavailable,
        );
        expect(await t.svc.checkRecoveryCancelled(sub), TransferStatus.unknown);
      },
    );
  });

  group('claimant countersign (offline only)', () {
    Future<
      ({OwnerWallet a, OwnerWallet b, FakeOwnerApi api, RecoveryRequest req})
    >
    setup({
      Map<String, dynamic> Function(OwnerWallet, OwnerWallet)? ledger,
    }) async {
      final a = await ownerWallet(ownerSeedA);
      final b = await ownerWallet(ownerSeedB);
      final api = FakeOwnerApi(
        ledger?.call(a, b) ??
            ledgerJson(stationId: a.session.stationId, owner: a.address),
      );
      return (
        a: a,
        b: b,
        api: api,
        req: RecoveryRequest(
          body: StationRecoveryBody(
            chainId: ownerDomain.chainId,
            networkId: ownerDomain.networkId,
            stationId: a.session.stationId,
            fromOwnerAddress: a.address,
            toOwnerAddress: b.address,
            toOwnerPubkey: b.pubkey,
            recoveryNonce: 3,
          ),
        ),
      );
    }

    StationOwnerService claimant(FakeOwnerApi api) => StationOwnerService(
      api: api,
      openSession: () async => (await ownerWallet(ownerSeedB)).session,
    );

    test(
      'countersigns the operator body and returns text; submits nothing',
      () async {
        final t = await setup();
        final flow = await claimant(t.api).beginRecoveryAccept(t.req.encode());
        expect(flow.request.body.toOwnerAddress, t.b.address);
        final text = await flow.countersign();
        flow.close();
        expect(t.api.submitted, isEmpty, reason: 'recovery accept is offline');
        final back = RecoveryAcceptText.decode(text);
        expect(back.body.stationId, t.req.body.stationId);
        expect(
          await verifyEd25519(
            t.b.pubkey,
            back.toOwnerSignature,
            stationOwnerRecoveryAcceptMessage(t.req.body),
          ),
          isTrue,
        );
      },
    );

    test('refuses every mismatch before signing', () async {
      final t = await setup();
      RecoveryRequest tweak({
        String? chain,
        String? to,
        String? toPub,
        int? nonce,
        String? from,
      }) => RecoveryRequest(
        body: StationRecoveryBody(
          chainId: chain ?? t.req.body.chainId,
          networkId: t.req.body.networkId,
          stationId: t.req.body.stationId,
          fromOwnerAddress: from ?? t.req.body.fromOwnerAddress,
          toOwnerAddress: to ?? t.req.body.toOwnerAddress,
          toOwnerPubkey: toPub ?? t.req.body.toOwnerPubkey,
          recoveryNonce: nonce ?? t.req.body.recoveryNonce,
        ),
      );
      final cases = <String, (RecoveryRequest, OfferProblem)>{
        'foreign chain': (tweak(chain: 'other'), OfferProblem.wrongChain),
        'not for me': (
          tweak(to: t.a.address.replaceFirst('0x', 'wrf')),
          OfferProblem.notForThisWallet,
        ),
        'wrong key': (tweak(toPub: t.a.pubkey), OfferProblem.notForThisWallet),
        'nonce moved': (tweak(nonce: 4), OfferProblem.nonceMismatch),
        'not the current owner': (
          tweak(from: t.b.address.replaceFirst('0x', 'wrf')),
          OfferProblem.notForThisWallet,
        ),
      };
      for (final e in cases.entries) {
        await expectLater(
          claimant(t.api).beginRecoveryAccept(e.value.$1.encode()),
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

    test('re-reads the ledger right before countersigning', () async {
      final t = await setup();
      final id = t.a.session.stationId;
      final moved = <String, Map<String, dynamic>>{
        'nonce moved': ledgerJson(stationId: id, owner: t.a.address, nonce: 4),
        'owner changed': ledgerJson(stationId: id, owner: t.b.address),
        'recovery filed meanwhile': ledgerJson(
          stationId: id,
          owner: t.a.address,
          pending: pending(from: t.a.address, to: t.b.address),
        ),
        'consent withdrawn': ledgerJson(
          stationId: id,
          owner: t.a.address,
          consent: false,
        ),
      };
      for (final e in moved.entries) {
        t.api.ledgerBody = ledgerJson(stationId: id, owner: t.a.address);
        final flow = await claimant(t.api).beginRecoveryAccept(t.req.encode());
        t.api.ledgerBody = e.value;
        await expectLater(
          flow.countersign(),
          throwsA(isA<OfferRejected>()),
          reason: e.key,
        );
        flow.close();
      }
      // a read failure at the last moment signs nothing either
      t.api.ledgerBody = ledgerJson(stationId: id, owner: t.a.address);
      final flow = await claimant(t.api).beginRecoveryAccept(t.req.encode());
      t.api.readError = const StationOwnerException(
        StationOwnerRefusal.unavailable,
      );
      await expectLater(
        flow.countersign(),
        throwsA(isA<StationOwnerException>()),
      );
      flow.close();
    });

    test('refuses stale ledger state', () async {
      final a = await ownerWallet(ownerSeedA);
      final b = await ownerWallet(ownerSeedB);
      final id = a.session.stationId;
      final ledgers = <String, (Map<String, dynamic>, OfferProblem)>{
        'owner changed': (
          ledgerJson(stationId: id, owner: b.address),
          OfferProblem.senderIsNotOwner,
        ),
        'consent inactive': (
          ledgerJson(stationId: id, owner: a.address, consent: false),
          OfferProblem.featureNotActive,
        ),
        'already pending': (
          ledgerJson(
            stationId: id,
            owner: a.address,
            pending: pending(from: a.address, to: b.address),
          ),
          OfferProblem.recoveryAlreadyPending,
        ),
      };
      final t = await setup();
      for (final e in ledgers.entries) {
        t.api.ledgerBody = e.value.$1;
        await expectLater(
          claimant(t.api).beginRecoveryAccept(t.req.encode()),
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
  });

  group('complete recovery (unsigned execute)', () {
    test(
      'refused until the window has passed; then submits unsigned',
      () async {
        final a = await ownerWallet(ownerSeedA);
        final b = await ownerWallet(ownerSeedB);
        final id = a.session.stationId;
        final api = FakeOwnerApi(
          ledgerJson(
            stationId: id,
            owner: a.address,
            observed: 20000,
            pending: pending(from: a.address, to: b.address),
          ),
        );
        final svc = StationOwnerService(
          api: api,
          openSession: () async => null,
        );
        await expectLater(
          svc.executeRecovery(id),
          throwsA(isA<StationOwnerBlocked>()),
        );
        expect(api.submitted, isEmpty);

        api.ledgerBody = ledgerJson(
          stationId: id,
          owner: a.address,
          observed: 34899,
          pending: pending(from: a.address, to: b.address),
        );
        final sub = await svc.executeRecovery(id);
        final tx = api.submitted.single;
        expect(tx.kind, 'recovery_execute');
        expect(jsonDecode(tx.payload), {
          'tx_kind': 'station_owner_recovery_execute_v1',
          'station_id': id,
          'recovery_nonce': 3,
        });
        expect(
          sub.toOwnerCommitment,
          ownerCommitment(id, b.address),
          reason: 'completion means the owner becomes the claimant commitment',
        );

        // applied only when the owner is the claimant and the nonce advanced
        expect(
          await svc.checkRecoveryExecuted(sub),
          TransferStatus.pendingConfirmation,
        );
        api.ledgerBody = ledgerJson(stationId: id, owner: b.address, nonce: 4);
        expect(await svc.checkRecoveryExecuted(sub), TransferStatus.confirmed);
      },
    );

    test('no pending recovery means nothing to complete', () async {
      final a = await ownerWallet(ownerSeedA);
      final id = a.session.stationId;
      final api = FakeOwnerApi(ledgerJson(stationId: id, owner: a.address));
      final svc = StationOwnerService(api: api, openSession: () async => null);
      await expectLater(
        svc.executeRecovery(id),
        throwsA(isA<StationOwnerBlocked>()),
      );
    });
  });

  group('shared operator<->phone vector (spec §13, docs/plans 0238445)', () {
    const requestText =
        'WRFOWN1.recovery.eyJ2IjoxLCJraW5kIjoic3RhdGlvbl9yZWNvdmVyeV9yZXF1ZXN0X3YxIiwiY2hhaW5faWQiOiJ3cmZjb2luLXRlc3RuZXQiLCJuZXR3b3JrX2lkIjoidGVzdG5ldCIsInN0YXRpb25faWQiOiJzdGF0aW9uLWdvbGRlbi0zMzQ1IiwiZnJvbV9vd25lcl9hZGRyZXNzIjoid3JmYTFhMWExYTFhMWExYTFhMWExYTFhMWExYTFhMWExYTFhMWExYTFhMSIsInRvX293bmVyX2FkZHJlc3MiOiJ3cmZjM2MzYzNjM2MzYzNjM2MzYzNjM2MzYzNjM2MzYzNjM2MzYzNjM2MzIiwidG9fb3duZXJfcHVia2V5IjoiYzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNCIsInJlY292ZXJ5X25vbmNlIjo3fQ.5278cf99';
    // NOTE: the reply text printed in spec §13 (rev 5) is truncated by 8
    // base64 characters (its signature decodes to 122 hex chars, and its own
    // sha256 is 97b7767d, not the stated 2292a693). This is the text rebuilt
    // from the spec's stated inputs by an independent Python implementation;
    // its checksum is the stated 2292a693.
    const replyText =
        'WRFOWN1.recovery-accept.eyJ2IjoxLCJraW5kIjoic3RhdGlvbl9yZWNvdmVyeV9hY2NlcHRfdjEiLCJjaGFpbl9pZCI6IndyZmNvaW4tdGVzdG5ldCIsIm5ldHdvcmtfaWQiOiJ0ZXN0bmV0Iiwic3RhdGlvbl9pZCI6InN0YXRpb24tZ29sZGVuLTMzNDUiLCJmcm9tX293bmVyX2FkZHJlc3MiOiJ3cmZhMWExYTFhMWExYTFhMWExYTFhMWExYTFhMWExYTFhMWExYTFhMWExIiwidG9fb3duZXJfYWRkcmVzcyI6IndyZmMzYzNjM2MzYzNjM2MzYzNjM2MzYzNjM2MzYzNjM2MzYzNjM2MzYzMiLCJ0b19vd25lcl9wdWJrZXkiOiJjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0YzRjNGM0IiwicmVjb3Zlcnlfbm9uY2UiOjcsInRvX293bmVyX3NpZ25hdHVyZSI6ImFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiIn0.2292a693';
    final body = StationRecoveryBody(
      chainId: 'wrfcoin-testnet',
      networkId: 'testnet',
      stationId: 'station-golden-3345',
      fromOwnerAddress: 'wrf${'a1' * 20}',
      toOwnerAddress: 'wrf${'c3' * 20}',
      toOwnerPubkey: 'c4' * 32,
      recoveryNonce: 7,
    );

    test('our request text equals the vector byte for byte', () {
      final text = RecoveryRequest(body: body).encode();
      expect(text, requestText);
      expect(text.endsWith('.5278cf99'), isTrue);
    });

    test('our reply text equals the vector byte for byte', () {
      final text = RecoveryAcceptText(
        body: body,
        toOwnerSignature: 'ab' * 64,
      ).encode();
      expect(text, replyText);
      expect(text.endsWith('.2292a693'), isTrue);
    });

    test('both vector texts decode to the inputs', () {
      final req = RecoveryRequest.decode(requestText);
      expect(req.body.stationId, 'station-golden-3345');
      expect(req.body.fromOwnerAddress, 'wrf${'a1' * 20}');
      expect(req.body.toOwnerAddress, 'wrf${'c3' * 20}');
      expect(req.body.toOwnerPubkey, 'c4' * 32);
      expect(req.body.recoveryNonce, 7);
      final rep = RecoveryAcceptText.decode(replyText);
      expect(rep.toOwnerSignature, 'ab' * 64);
      expect(rep.body.recoveryNonce, 7);
      // wrapped pastes still decode
      expect(
        RecoveryRequest.decode(
          '${requestText.substring(0, 50)}\n${requestText.substring(50)}',
        ).body.stationId,
        'station-golden-3345',
      );
    });
  });

  test('approximate wait is clearly an estimate', () {
    expect(approxRecoveryWait(blocksRemaining: 0), 'any moment now');
    expect(approxRecoveryWait(blocksRemaining: 34000), contains('14 days'));
    expect(approxRecoveryWait(blocksRemaining: 2400), contains('hour'));
  });
}
