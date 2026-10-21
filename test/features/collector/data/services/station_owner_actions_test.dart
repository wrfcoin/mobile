import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_exchange.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_service.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../../station_owner_fixtures.dart';

void main() {
  group('owner action payload', () {
    test('field set and order match the relay contract', () {
      final json = ownerActionPayloadJson(
        stationId: 'st',
        ownerAddress: '0xa',
        ownerPubkey: 'b' * 64,
        action: StationOwnerAction.reportStolen,
        actionNonce: 7,
        expiresAtHeight: 21000,
        ownerSignature: 'c' * 128,
      );
      final m = jsonDecode(json) as Map<String, dynamic>;
      expect(m.keys.toList(), [
        'tx_kind',
        'station_id',
        'owner_address',
        'owner_pubkey',
        'action',
        'action_nonce',
        'expires_at_height',
        'owner_signature',
      ]);
      expect(m['tx_kind'], 'station_owner_action_v1');
      expect(m['action'], 'report_stolen');
      expect(m['action_nonce'], 7);
    });

    test('all four actions are shippable (goldens: core4 8457a09a2)', () {
      expect(StationOwnerAction.values.every((a) => a.shippable), isTrue);
    });
  });

  group('StationOwnerService.performOwnerAction', () {
    Future<({OwnerWallet a, FakeOwnerApi api, StationOwnerService svc})> setup({
      Map<String, dynamic>? ledger,
    }) async {
      final a = await ownerWallet(ownerSeedA);
      final api = FakeOwnerApi(
        ledger ?? ledgerJson(stationId: a.session.stationId, owner: a.address),
      );
      return (
        a: a,
        api: api,
        svc: StationOwnerService(
          api: api,
          openSession: () async => (await ownerWallet(ownerSeedA)).session,
        ),
      );
    }

    test('report_stolen signs at ledger nonce, tip+5000, owner key', () async {
      final t = await setup();
      final sub = await t.svc.performOwnerAction(
        StationOwnerAction.reportStolen,
      );
      expect(t.api.submitted, hasLength(1));
      final tx = t.api.submitted.single;
      expect(tx.kind, 'owner_action');
      expect(tx.stationId, t.a.session.stationId);
      final m = jsonDecode(tx.payload) as Map<String, dynamic>;
      expect(m['action'], 'report_stolen');
      expect(m['action_nonce'], 3);
      expect(m['expires_at_height'], 6000);
      expect(m['owner_address'], t.a.address);
      expect(m['owner_pubkey'], t.a.pubkey);
      expect(
        await verifyEd25519(
          m['owner_pubkey'] as String,
          m['owner_signature'] as String,
          stationOwnerActionMessage(
            chainId: ownerDomain.chainId,
            networkId: ownerDomain.networkId,
            stationId: t.a.session.stationId,
            ownerAddress: t.a.address,
            action: StationOwnerAction.reportStolen,
            actionNonce: 3,
            expiresAtHeight: 6000,
          ),
        ),
        isTrue,
      );
      expect(sub.baselineNonce, 3);
    });

    test('refuses before signing when the ledger forbids it', () async {
      final a = await ownerWallet(ownerSeedA);
      final b = await ownerWallet(ownerSeedB);
      final id = a.session.stationId;
      final cases = <String, Map<String, dynamic>>{
        'actions inactive': ledgerJson(
          stationId: id,
          owner: a.address,
          actions: false,
        ),
        'not the owner': ledgerJson(stationId: id, owner: b.address),
        'already frozen': ledgerJson(
          stationId: id,
          owner: a.address,
          frozen: {'since_height': 1},
        ),
      };
      for (final e in cases.entries) {
        final t = await setup(ledger: e.value);
        await expectLater(
          t.svc.performOwnerAction(StationOwnerAction.reportStolen),
          throwsA(isA<StationOwnerBlocked>()),
          reason: e.key,
        );
        expect(t.api.submitted, isEmpty, reason: e.key);
      }
    });

    test('each action is allowed only in its own ledger state', () async {
      final a = await ownerWallet(ownerSeedA);
      final id = a.session.stationId;
      Map<String, dynamic> l({Object? frozen, bool deactivated = false}) =>
          ledgerJson(
            stationId: id,
            owner: a.address,
            frozen: frozen,
            deactivated: deactivated,
          );
      final frozen = {'since_height': 5};
      // action -> (allowed ledger, a ledger that must be refused)
      final cases =
          <StationOwnerAction, (Map<String, dynamic>, Map<String, dynamic>)>{
            StationOwnerAction.reportStolen: (l(), l(frozen: frozen)),
            StationOwnerAction.unfreeze: (l(frozen: frozen), l()),
            StationOwnerAction.deactivate: (l(), l(deactivated: true)),
            StationOwnerAction.reactivate: (l(deactivated: true), l()),
          };
      for (final e in cases.entries) {
        final ok = await setup(ledger: e.value.$1);
        await ok.svc.performOwnerAction(e.key);
        final m =
            jsonDecode(ok.api.submitted.single.payload) as Map<String, dynamic>;
        expect(m['action'], e.key.wireName);
        expect(
          await verifyEd25519(
            m['owner_pubkey'] as String,
            m['owner_signature'] as String,
            stationOwnerActionMessage(
              chainId: ownerDomain.chainId,
              networkId: ownerDomain.networkId,
              stationId: id,
              ownerAddress: a.address,
              action: e.key,
              actionNonce: 3,
              expiresAtHeight: 6000,
            ),
          ),
          isTrue,
          reason: e.key.wireName,
        );
        final bad = await setup(ledger: e.value.$2);
        await expectLater(
          bad.svc.performOwnerAction(e.key),
          throwsA(isA<StationOwnerBlocked>()),
          reason: e.key.wireName,
        );
        expect(bad.api.submitted, isEmpty, reason: e.key.wireName);
      }
    });

    test('ownership is the commitment, never the displayed owner', () async {
      final a = await ownerWallet(ownerSeedA);
      final b = await ownerWallet(ownerSeedB);
      // The registered owner is B, but the display field mimics A's short form.
      final ledger =
          ledgerJson(stationId: a.session.stationId, owner: b.address)
            ..['owner'] =
                '${a.address.substring(0, 6)}…${a.address.substring(a.address.length - 4)}';
      final t = await setup(ledger: ledger);
      await expectLater(
        t.svc.performOwnerAction(StationOwnerAction.reportStolen),
        throwsA(isA<StationOwnerBlocked>()),
      );
      expect(t.api.submitted, isEmpty);
    });

    test('a frozen station cannot be deactivated or reactivated', () async {
      final a = await ownerWallet(ownerSeedA);
      final id = a.session.stationId;
      for (final action in [
        StationOwnerAction.deactivate,
        StationOwnerAction.reactivate,
      ]) {
        final t = await setup(
          ledger: ledgerJson(
            stationId: id,
            owner: a.address,
            frozen: {'since_height': 1},
            deactivated: action == StationOwnerAction.reactivate,
          ),
        );
        await expectLater(
          t.svc.performOwnerAction(action),
          throwsA(isA<StationOwnerBlocked>()),
        );
      }
    });

    test('submit refusals surface typed', () async {
      final t = await setup();
      t.api.submitError = const StationOwnerException(
        StationOwnerRefusal.stationFrozen,
        code: 'OWNER_TX_STATION_FROZEN',
      );
      await expectLater(
        t.svc.performOwnerAction(StationOwnerAction.reportStolen),
        throwsA(
          isA<StationOwnerException>().having(
            (e) => e.refusal,
            'refusal',
            StationOwnerRefusal.stationFrozen,
          ),
        ),
      );
    });

    test(
      'a 201 is pending; applied only when the ledger shows the effect',
      () async {
        final t = await setup();
        final sub = await t.svc.performOwnerAction(
          StationOwnerAction.reportStolen,
        );
        final id = sub.stationId;
        expect(
          await t.svc.checkActionApplied(sub),
          TransferStatus.pendingConfirmation,
        );
        // nonce advanced but not frozen: still pending
        t.api.ledgerBody = ledgerJson(
          stationId: id,
          owner: t.a.address,
          nonce: 4,
        );
        expect(
          await t.svc.checkActionApplied(sub),
          TransferStatus.pendingConfirmation,
        );
        // frozen but nonce not advanced: still pending
        t.api.ledgerBody = ledgerJson(
          stationId: id,
          owner: t.a.address,
          frozen: {'since_height': 10},
        );
        expect(
          await t.svc.checkActionApplied(sub),
          TransferStatus.pendingConfirmation,
        );
        t.api.ledgerBody = ledgerJson(
          stationId: id,
          owner: t.a.address,
          nonce: 4,
          frozen: {'since_height': 10},
        );
        expect(await t.svc.checkActionApplied(sub), TransferStatus.confirmed);
        t.api.readError = const StationOwnerException(
          StationOwnerRefusal.unavailable,
        );
        expect(await t.svc.checkActionApplied(sub), TransferStatus.unknown);
      },
    );

    test(
      'each action confirms only on nonce advance AND its own effect',
      () async {
        final a = await ownerWallet(ownerSeedA);
        final id = a.session.stationId;
        const frozen = {'since_height': 9};
        final effects =
            <
              StationOwnerAction,
              ({Map<String, dynamic> before, Map<String, dynamic> after})
            >{
              StationOwnerAction.unfreeze: (
                before: ledgerJson(
                  stationId: id,
                  owner: a.address,
                  frozen: frozen,
                ),
                after: ledgerJson(stationId: id, owner: a.address, nonce: 4),
              ),
              StationOwnerAction.deactivate: (
                before: ledgerJson(stationId: id, owner: a.address),
                after: ledgerJson(
                  stationId: id,
                  owner: a.address,
                  nonce: 4,
                  deactivated: true,
                ),
              ),
              StationOwnerAction.reactivate: (
                before: ledgerJson(
                  stationId: id,
                  owner: a.address,
                  deactivated: true,
                ),
                after: ledgerJson(stationId: id, owner: a.address, nonce: 4),
              ),
            };
        for (final e in effects.entries) {
          final t = await setup(ledger: e.value.before);
          final sub = await t.svc.performOwnerAction(e.key);
          expect(
            await t.svc.checkActionApplied(sub),
            TransferStatus.pendingConfirmation,
            reason: e.key.wireName,
          );
          // effect visible but nonce not advanced: still pending
          t.api.ledgerBody = {...e.value.after, 'ownerNonce': 3};
          expect(
            await t.svc.checkActionApplied(sub),
            TransferStatus.pendingConfirmation,
            reason: e.key.wireName,
          );
          t.api.ledgerBody = e.value.after;
          expect(
            await t.svc.checkActionApplied(sub),
            TransferStatus.confirmed,
            reason: e.key.wireName,
          );
        }
      },
    );

    test('a biometric refusal cancels without signing', () async {
      final api = FakeOwnerApi(ledgerJson());
      final svc = StationOwnerService(api: api, openSession: () async => null);
      await expectLater(
        svc.performOwnerAction(StationOwnerAction.reportStolen),
        throwsA(isA<StationOwnerCancelled>()),
      );
    });
  });
}
