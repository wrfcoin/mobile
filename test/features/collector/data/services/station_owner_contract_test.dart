import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/models/station_owner_models.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_owner_api.dart';

// The backend contract fixture (backend#1459, __tests__/fixtures/
// station-owner-contract.json), copied byte for byte. It is generated from the
// REAL relay routes; do not edit it here, regenerate it there.
const _fixturePath =
    'test/features/collector/fixtures/station-owner-contract.json';
const _fixtureSha256 =
    '0b6cb2b4f9e60a77e56aa10b33ecbd6f5f2148dad65148913597705a593ba633';

late final Map<String, dynamic> _fixture;
late final Map<String, dynamic> _cases;
late final Map<String, dynamic> _constants;

String get _stationId => _constants['stationId'] as String;
String get _ownerAddress => _constants['ownerAddress'] as String;

DioStationOwnerApi _replying(Map<String, dynamic> response) {
  final status = response['status'] as int;
  final body = response['body'];
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        final res = Response(requestOptions: o, statusCode: status, data: body);
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

SignedOwnerPayload _signed(String kind, String payload) =>
    SignedOwnerPayload(stationId: _stationId, kind: kind, payload: payload);

void main() {
  setUpAll(() {
    final bytes = File(_fixturePath).readAsBytesSync();
    expect(
      crypto.sha256.convert(bytes).toString(),
      _fixtureSha256,
      reason: 'the fixture must be the backend file, byte for byte',
    );
    _fixture = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    _cases = _fixture['cases'] as Map<String, dynamic>;
    _constants = _fixture['constants'] as Map<String, dynamic>;
  });

  test('all 23 backend cases are covered by this file', () {
    const covered = {
      'ownership_owner_view',
      'ownership_new_owner_view',
      'ownership_non_owner_view',
      'ownership_clean',
      'ownership_404_unknown_alias',
      'ownership_404_not_registered',
      'ownership_502_contract_mismatch_frozen_omitted',
      'ownership_503_node_down',
      'submit_201_owner_action',
      'submit_201_transfer_by_new_owner',
      'submit_201_recovery_execute_no_login',
      'submit_401_login_required',
      'submit_403_not_the_signer',
      'submit_403_recovery_file_not_offered',
      'submit_404_unknown_alias',
      'submit_413_body_too_large',
      'submit_422_invalid_owner_action',
      'submit_422_unsupported_kind_recovery_accept',
      'submit_422_node_code_nonce_mismatch',
      'submit_422_node_code_chain_identity_mismatch',
      'submit_429_rate_limited',
      'submit_503_node_unavailable',
      'submit_503_relay_credential_unconfigured',
    };
    expect(_cases.keys.toSet(), covered);
  });

  group('ownership read', () {
    for (final name in [
      'ownership_owner_view',
      'ownership_new_owner_view',
      'ownership_non_owner_view',
      'ownership_clean',
    ]) {
      test('$name parses and matches the owner by commitment', () async {
        final response = _cases[name]['response'] as Map<String, dynamic>;
        final l = await _replying(response).readLedger(_stationId);
        final body = response['body'] as Map<String, dynamic>;
        expect(l.isOwner, body['isOwner']);
        expect(l.ownerNonce, body['ownerNonce']);
        expect(l.frozen, body['frozen'] != null);
        expect(l.consentActive, isTrue);
        // The registered owner matches in either spelling of the same bytes.
        expect(l.ownerIs(_stationId, _ownerAddress), isTrue);
        expect(
          l.ownerIs(_stationId, _ownerAddress.replaceFirst('0x', 'wrf')),
          isTrue,
        );
        expect(
          l.ownerIs(_stationId, _ownerAddress.replaceFirst('0x', 'WRF')),
          isTrue,
        );
        expect(
          l.ownerIs(_stationId, _constants['newOwnerAddress'] as String),
          isFalse,
        );
        expect(
          l.ownerIs(_stationId, _constants['strangerAddress'] as String),
          isFalse,
        );
        expect(l.ownerIs('another-station', _ownerAddress), isFalse);
        // the short display form is never a basis for a match
        expect(l.ownerIs(_stationId, '0xa1a1…a1a1'), isFalse);
      });
    }

    test('a pending recovery carries both commitments', () async {
      final response =
          _cases['ownership_non_owner_view']['response']
              as Map<String, dynamic>;
      final l = await _replying(response).readLedger(_stationId);
      final p = l.pendingRecovery!;
      expect(p.recoveryNonce, 7);
      expect(p.executableAtHeight, 35000);
      expect(p.noticeBlocks, 34000);
      expect(p.fromOwnerCommitment, ownerCommitment(_stationId, _ownerAddress));
      expect(
        p.toOwnerCommitment,
        ownerCommitment(_stationId, _constants['newOwnerAddress'] as String),
      );
    });

    test(
      'the owner view shows the full owner; others the short form',
      () async {
        Future<OwnerLedger> read(String n) =>
            _replying(_cases[n]['response'] as Map<String, dynamic>)
                .readLedger(_stationId);
        expect((await read('ownership_owner_view')).owner, _ownerAddress);
        expect((await read('ownership_non_owner_view')).owner, contains('…'));
      },
    );

    final errors = <String, StationOwnerRefusal>{
      'ownership_404_unknown_alias': StationOwnerRefusal.stationNotFound,
      'ownership_404_not_registered': StationOwnerRefusal.stationNotRegistered,
      'ownership_502_contract_mismatch_frozen_omitted':
          StationOwnerRefusal.unavailable,
      'ownership_503_node_down': StationOwnerRefusal.unavailable,
    };
    for (final e in errors.entries) {
      test('${e.key} is ${e.value.name}, never a pass', () async {
        final response = _cases[e.key]['response'] as Map<String, dynamic>;
        try {
          await _replying(response).readLedger(_stationId);
          fail('expected a failure');
        } on StationOwnerException catch (x) {
          expect(x.refusal, e.value);
        }
      });
    }
  });

  group('submit', () {
    for (final name in [
      'submit_201_owner_action',
      'submit_201_transfer_by_new_owner',
      'submit_201_recovery_execute_no_login',
    ]) {
      test('$name is accepted-pending with ids and a height', () async {
        final response = _cases[name]['response'] as Map<String, dynamic>;
        final r = await _replying(response).submit(_signed('transfer', '{}'));
        final body = response['body'] as Map<String, dynamic>;
        expect(r.transactionIds, body['transactionIds']);
        expect(r.admissionHeight, body['admissionHeight']);
        expect(
          (body['kind'] as String).startsWith('station_owner_'),
          isTrue,
          reason: 'the 201 kind is the node tx_kind, not the request kind',
        );
      });
    }

    final errors = <String, StationOwnerRefusal>{
      'submit_401_login_required': StationOwnerRefusal.loginRequired,
      'submit_403_not_the_signer': StationOwnerRefusal.notTheSigner,
      'submit_403_recovery_file_not_offered': StationOwnerRefusal.notOffered,
      'submit_404_unknown_alias': StationOwnerRefusal.stationNotFound,
      'submit_413_body_too_large': StationOwnerRefusal.unknown,
      'submit_422_invalid_owner_action': StationOwnerRefusal.invalidOwnerAction,
      'submit_422_unsupported_kind_recovery_accept':
          StationOwnerRefusal.notOffered,
      'submit_422_node_code_nonce_mismatch': StationOwnerRefusal.nonceMismatch,
      'submit_422_node_code_chain_identity_mismatch':
          StationOwnerRefusal.chainIdentityMismatch,
      'submit_429_rate_limited': StationOwnerRefusal.rateLimited,
      'submit_503_node_unavailable': StationOwnerRefusal.unavailable,
      'submit_503_relay_credential_unconfigured':
          StationOwnerRefusal.unavailable,
    };
    for (final e in errors.entries) {
      test('${e.key} is ${e.value.name}', () async {
        final response = _cases[e.key]['response'] as Map<String, dynamic>;
        try {
          await _replying(response).submit(_signed('owner_action', '{}'));
          fail('expected a failure');
        } on StationOwnerException catch (x) {
          expect(x.refusal, e.value);
          // the human text is ours, never the server's
          expect(x.refusal.userMessage, isNot(contains('credential')));
        }
      });
    }
  });

  group(
    'request body: the payload object is posted as the exact signed text',
    () {
      test(
        'body is {"kind":..,"payload":<signed text>}, byte for byte',
        () async {
          // Deliberately odd spacing and key order: any re-encoding would show.
          const signed =
              '{"tx_kind":"station_owner_action_v1",  "z":1,\n "a":2 }';
          late RequestOptions seen;
          final dio = Dio();
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                seen = o;
                h.resolve(
                  Response(
                    requestOptions: o,
                    statusCode: 201,
                    data:
                        (_cases['submit_201_owner_action']['response']
                            as Map<String, dynamic>)['body'],
                  ),
                );
              },
            ),
          );
          await DioStationOwnerApi(dio).submit(_signed('owner_action', signed));
          expect(seen.data, isA<String>());
          expect(seen.data, '{"kind":"owner_action","payload":$signed}');
          expect(
            seen.path,
            '/stations/${stationAliasOf(_stationId)}/owner-actions',
          );
          expect(
            seen.headers['content-type'] ?? seen.contentType,
            contains('json'),
          );
        },
      );

      test('the fixture request shapes use the same {kind, payload} form', () {
        for (final e in _cases.entries.where(
          (e) => e.key.startsWith('submit_201'),
        )) {
          final body = e.value['request']['body'] as Map<String, dynamic>;
          expect(body.keys.toSet(), {'kind', 'payload'});
          expect(body['payload'], isA<Map<String, dynamic>>());
        }
      });
    },
  );

  group('station alias and owner commitment', () {
    test('alias matches the backend constant', () {
      expect(stationAliasOf(_stationId), _constants['stationAlias']);
    });

    test('the formula vector is pinned', () {
      final v = _constants['ownerCommitmentVector'] as Map<String, dynamic>;
      expect(
        ownerCommitment(v['stationId'] as String, v['address'] as String),
        v['commitment'],
      );
      expect(
        ownerCommitment('PWS-DULUTH-PRIVATENAME-01', '0x${'a1' * 20}'),
        '4f0803cf5968a5e36b0893b1cef89f119d4f47cfdd4b509ff684e42249d180fd',
      );
    });

    test('0x, wrf and WRF spellings of the same 20 bytes agree', () {
      final c = ownerCommitment(_stationId, '0x${'a1' * 20}');
      expect(ownerCommitment(_stationId, 'wrf${'a1' * 20}'), c);
      expect(ownerCommitment(_stationId, 'WRF${'a1' * 20}'), c);
      expect(ownerCommitment(_stationId, '0x${'A1' * 20}'), c);
      expect(ownerCommitment(_stationId, 'a1' * 20), c, reason: 'bare hex');
    });

    test('anything that is not exactly 40 hex digits is refused', () {
      for (final bad in [
        '',
        '0x',
        '0xa1',
        '0xa1…a1a1',
        '0x${'a1' * 21}',
        '0x${'zz' * 20}',
        'wrf${'a1' * 19}',
      ]) {
        expect(
          () => ownerCommitment(_stationId, bad),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('the station id is RAW: it changes the commitment', () {
      expect(
        ownerCommitment('a', '0x${'a1' * 20}'),
        isNot(ownerCommitment('b', '0x${'a1' * 20}')),
      );
    });
  });

  group('strict ownership parsing', () {
    Map<String, dynamic> clean() => Map<String, dynamic>.from(
      (_cases['ownership_clean']['response'] as Map)['body'] as Map,
    );

    test('every key is required; none defaults to "not frozen"', () {
      for (final key in [
        'ownerCommitment',
        'ownerNonce',
        'frozen',
        'ownerDeactivated',
        'pendingRecovery',
        'features',
        'observedAtHeight',
        'settledHeight',
        'rewardsSuspended',
        'isOwner',
        'owner',
      ]) {
        expect(
          () => OwnerLedger.fromJson(clean()..remove(key)),
          throwsFormatException,
          reason: key,
        );
      }
      expect(
        () => OwnerLedger.fromJson(
          clean()..['features'] = {'stationOwnerConsent': true},
        ),
        throwsFormatException,
      );
      expect(
        () => OwnerLedger.fromJson(clean()..['ownerCommitment'] = 'XYZ'),
        throwsFormatException,
      );
    });

    test('a pending recovery missing a commitment is rejected', () {
      final body = Map<String, dynamic>.from(
        (_cases['ownership_non_owner_view']['response'] as Map)['body'] as Map,
      );
      final p = Map<String, dynamic>.from(body['pendingRecovery'] as Map)
        ..remove('toOwnerCommitment');
      expect(
        () => OwnerLedger.fromJson(body..['pendingRecovery'] = p),
        throwsFormatException,
      );
    });

    test('the old node snake_case shape is NOT accepted', () {
      expect(
        () => OwnerLedger.fromJson({
          'station_id': 's',
          'owner_address': 'wrfa',
          'owner_ledger': {'owner_nonce': 1},
        }),
        throwsFormatException,
      );
    });
  });
}
