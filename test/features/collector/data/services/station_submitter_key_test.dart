import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_exchange.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_service.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';

import '../../station_owner_fixtures.dart';

final _phoneKey = 'c4' * 32;

Map<String, dynamic> _ledger(
  String stationId,
  String owner, {
  bool? active = true,
  Object? submitter = const _Absent(),
  Object? frozen,
  int nonce = 3,
}) {
  final j = ledgerJson(
    stationId: stationId,
    owner: owner,
    nonce: nonce,
    frozen: frozen,
  );
  if (active != null) {
    (j['features'] as Map)['stationSubmitterKey'] = active;
  }
  if (submitter is! _Absent) j['submitterKey'] = submitter;
  return j;
}

class _Absent {
  const _Absent();
}

Future<(StationOwnerService, FakeOwnerApi, OwnerWallet)> _svc({
  bool? active = true,
  Object? submitter = const _Absent(),
  Object? frozen,
  String? collectKey,
  bool otherOwner = false,
}) async {
  final w = await ownerWallet(ownerSeedA);
  final owner = otherOwner
      ? (await ownerWallet(ownerSeedB)).address
      : w.address;
  final api = FakeOwnerApi(
    _ledger(
      w.session.stationId,
      owner,
      active: active,
      submitter: submitter,
      frozen: frozen,
    ),
  );
  final svc = StationOwnerService(
    api: api,
    openSession: () async => (await ownerWallet(ownerSeedA)).session,
    loadCollectPubkey: (_) async => collectKey,
  );
  return (svc, api, w);
}

void main() {
  group('ownership read: station_submitter_key fields', () {
    test('an older backend without the fields reads as inactive/unknown', () {
      final l = OwnerLedger.fromJson(ledgerJson());
      expect(l.submitterKeyActive, isFalse);
      expect(l.submitterKeyReported, isFalse);
      expect(l.submitterKey, isNull);
    });

    test('parses the flag and the key strictly', () {
      final j = ledgerJson();
      (j['features'] as Map)['stationSubmitterKey'] = true;
      j['submitterKey'] = {'pubkey': _phoneKey, 'class': 'device'};
      final l = OwnerLedger.fromJson(j);
      expect(l.submitterKeyActive, isTrue);
      expect(l.submitterKeyReported, isTrue);
      expect(l.submitterKey!.pubkey, _phoneKey);
      expect(l.submitterKey!.submitterClass, SubmitterClass.device);

      j['submitterKey'] = null;
      final none = OwnerLedger.fromJson(j);
      expect(none.submitterKeyReported, isTrue);
      expect(none.submitterKey, isNull);

      for (final bad in <Object>[
        'x',
        {'pubkey': _phoneKey, 'class': 'phone'},
        {'pubkey': _phoneKey.toUpperCase(), 'class': 'device'},
        {'class': 'device'},
      ]) {
        j['submitterKey'] = bad;
        expect(() => OwnerLedger.fromJson(j), throwsFormatException);
      }
      j['submitterKey'] = null;
      j['features'] = <String, Object>{
        ...(j['features'] as Map<String, dynamic>),
        'stationSubmitterKey': 'yes',
      };
      expect(() => OwnerLedger.fromJson(j), throwsFormatException);
    });
  });

  group('payload JSON (core4 StationSubmitterKeyPayload)', () {
    test('approve carries key and class; clear omits both', () {
      final set = jsonDecode(
        setSubmitterKeyPayloadJson(
          stationId: 'mob-1',
          ownerAddress: '0xab',
          ownerPubkey: 'ee' * 32,
          submitterPubkey: _phoneKey,
          submitterClass: SubmitterClass.device,
          actionNonce: 3,
          expiresAtHeight: 6000,
          ownerSignature: 'ff' * 64,
        ),
      ) as Map<String, dynamic>;
      expect(set, {
        'tx_kind': 'station_owner_action_v1',
        'station_id': 'mob-1',
        'owner_address': '0xab',
        'owner_pubkey': 'ee' * 32,
        'action': 'set_submitter_key',
        'action_nonce': 3,
        'expires_at_height': 6000,
        'owner_signature': 'ff' * 64,
        'submitter_pubkey': _phoneKey,
        'submitter_class': 'device',
      });
      final clear = jsonDecode(
        setSubmitterKeyPayloadJson(
          stationId: 'mob-1',
          ownerAddress: '0xab',
          ownerPubkey: 'ee' * 32,
          submitterPubkey: null,
          submitterClass: null,
          actionNonce: 3,
          expiresAtHeight: 6000,
          ownerSignature: 'ff' * 64,
        ),
      ) as Map<String, dynamic>;
      expect(clear.containsKey('submitter_pubkey'), isFalse);
      expect(clear.containsKey('submitter_class'), isFalse);
      expect(clear['action'], 'set_submitter_key');
    });

    test('refuses a half-set pair', () {
      expect(
        () => setSubmitterKeyPayloadJson(
          stationId: 'mob-1',
          ownerAddress: '0xab',
          ownerPubkey: 'ee' * 32,
          submitterPubkey: _phoneKey,
          submitterClass: null,
          actionNonce: 3,
          expiresAtHeight: 6000,
          ownerSignature: 'ff' * 64,
        ),
        throwsArgumentError,
      );
    });
  });

  group('approve this phone / clear', () {
    test('approve signs this phone key as Device and submits', () async {
      final (svc, api, w) = await _svc(submitter: null, collectKey: _phoneKey);
      final sub = await svc.approveThisPhoneAsSubmitter();
      expect(api.submitted, hasLength(1));
      final tx = api.submitted.single;
      expect(tx.kind, 'owner_action');
      final p = jsonDecode(tx.payload) as Map<String, dynamic>;
      expect(p['action'], 'set_submitter_key');
      expect(p['submitter_pubkey'], _phoneKey);
      expect(p['submitter_class'], 'device');
      expect(p['owner_address'], w.address);
      expect(p['action_nonce'], 3);
      expect(p['expires_at_height'], 1000 + ownerTxExpiryBlocks);
      final msg = stationOwnerSetSubmitterMessage(
        chainId: ownerDomain.chainId,
        networkId: ownerDomain.networkId,
        stationId: w.session.stationId,
        ownerAddress: w.address,
        actionNonce: 3,
        expiresAtHeight: 1000 + ownerTxExpiryBlocks,
        submitterPubkey: _phoneKey,
        submitterClass: SubmitterClass.device,
      );
      expect(
        await verifyEd25519(
          p['owner_pubkey'] as String,
          p['owner_signature'] as String,
          msg,
        ),
        isTrue,
      );
      expect(sub.submitterPubkey, _phoneKey);
      expect(sub.baselineNonce, 3);
    });

    test('clear signs without key and class', () async {
      final (svc, api, w) = await _svc(
        submitter: {'pubkey': _phoneKey, 'class': 'device'},
      );
      final sub = await svc.clearSubmitterKey();
      final p =
          jsonDecode(api.submitted.single.payload) as Map<String, dynamic>;
      expect(p.containsKey('submitter_pubkey'), isFalse);
      expect(p.containsKey('submitter_class'), isFalse);
      final msg = stationOwnerSetSubmitterMessage(
        chainId: ownerDomain.chainId,
        networkId: ownerDomain.networkId,
        stationId: w.session.stationId,
        ownerAddress: w.address,
        actionNonce: 3,
        expiresAtHeight: 1000 + ownerTxExpiryBlocks,
        submitterPubkey: null,
        submitterClass: null,
      );
      expect(
        await verifyEd25519(
          p['owner_pubkey'] as String,
          p['owner_signature'] as String,
          msg,
        ),
        isTrue,
      );
      expect(sub.submitterPubkey, isNull);
    });

    final blocked =
        <
          String,
          Future<(StationOwnerService, FakeOwnerApi, OwnerWallet)> Function()
        >{
          'feature flag absent (inert today)': () =>
              _svc(active: null, collectKey: _phoneKey),
          'feature inactive': () => _svc(active: false, collectKey: _phoneKey),
          'not the owner': () => _svc(otherOwner: true, collectKey: _phoneKey),
          'station frozen': () =>
              _svc(frozen: {'since_height': 900}, collectKey: _phoneKey),
          'no collect key on this phone': () => _svc(submitter: null),
          'already approved': () => _svc(
            submitter: {'pubkey': _phoneKey, 'class': 'device'},
            collectKey: _phoneKey,
          ),
        };
    for (final e in blocked.entries) {
      test('approve refused before signing: ${e.key}', () async {
        final (svc, api, _) = await e.value();
        await expectLater(
          svc.approveThisPhoneAsSubmitter(),
          throwsA(isA<StationOwnerBlocked>()),
        );
        expect(api.submitted, isEmpty);
      });
    }

    test('clear refused when the read shows no key', () async {
      final (svc, api, _) = await _svc(submitter: null);
      await expectLater(
        svc.clearSubmitterKey(),
        throwsA(isA<StationOwnerBlocked>()),
      );
      expect(api.submitted, isEmpty);
    });

    test('cancelled biometric signs nothing', () async {
      final api = FakeOwnerApi(ledgerJson());
      final svc = StationOwnerService(
        api: api,
        openSession: () async => null,
        loadCollectPubkey: (_) async => _phoneKey,
      );
      await expectLater(
        svc.approveThisPhoneAsSubmitter(),
        throwsA(isA<StationOwnerCancelled>()),
      );
      expect(api.submitted, isEmpty);
    });
  });

  group('checkSubmitterApplied', () {
    SubmitterKeySubmission sub(String? key) => SubmitterKeySubmission(
      stationId: 'st',
      submitterPubkey: key,
      baselineNonce: 3,
      receipt: const OwnerSubmitReceipt(
        transactionIds: ['aa'],
        admissionHeight: 1,
      ),
    );

    test('confirmed only when the nonce advanced and the key shows', () async {
      final api = FakeOwnerApi(
        _ledger('st', '0x${'e5' * 20}', submitter: null),
      );
      final svc = StationOwnerService(api: api, openSession: () async => null);
      expect(
        await svc.checkSubmitterApplied(sub(_phoneKey)),
        TransferStatus.pendingConfirmation,
      );
      api.ledgerBody = _ledger(
        'st',
        '0x${'e5' * 20}',
        nonce: 3,
        submitter: {'pubkey': _phoneKey, 'class': 'device'},
      );
      expect(
        await svc.checkSubmitterApplied(sub(_phoneKey)),
        TransferStatus.pendingConfirmation,
        reason: 'nonce did not advance',
      );
      api.ledgerBody = _ledger(
        'st',
        '0x${'e5' * 20}',
        nonce: 4,
        submitter: {'pubkey': _phoneKey, 'class': 'device'},
      );
      expect(
        await svc.checkSubmitterApplied(sub(_phoneKey)),
        TransferStatus.confirmed,
      );
      api.ledgerBody = _ledger(
        'st',
        '0x${'e5' * 20}',
        nonce: 4,
        submitter: null,
      );
      expect(
        await svc.checkSubmitterApplied(sub(null)),
        TransferStatus.confirmed,
      );
    });

    test('a read that does not report the key never confirms', () async {
      final api = FakeOwnerApi(_ledger('st', '0x${'e5' * 20}', nonce: 9));
      final svc = StationOwnerService(api: api, openSession: () async => null);
      expect(
        await svc.checkSubmitterApplied(sub(null)),
        TransferStatus.pendingConfirmation,
      );
    });

    test('a failed read is unknown', () async {
      final api = FakeOwnerApi(ledgerJson())
        ..readError = const StationOwnerException(
          StationOwnerRefusal.unavailable,
        );
      final svc = StationOwnerService(api: api, openSession: () async => null);
      expect(
        await svc.checkSubmitterApplied(sub(_phoneKey)),
        TransferStatus.unknown,
      );
    });
  });
}
