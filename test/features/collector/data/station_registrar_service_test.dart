import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/collector/data/services/station_registrar_service.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/crypto/station_signing.dart';
import 'package:wrfcoin_mobile/services/crypto/transfer_signing_domain.dart';

import '../../../test_helpers/fake_station_backend.dart';

// Synthetic wallet only (seed [7; 32]); no real account, key or location.
typedef Answer = (int, Object?);

class _Backend {
  _Backend();

  final requests = <RequestOptions>[];
  Answer networkStatus = (200, _active(['station_registrar_key']));
  Answer status = (404, _error('NOT_REQUESTED'));
  Answer mobile = (
    200,
    {
      'stationId': syntheticStationId,
      'status': 'db_only',
      'cell': {'latE1': 377, 'lonE1': -1224},
    },
  );
  Answer post = (
    202,
    {
      'ok': true,
      'data': {
        'stationId': syntheticStationId,
        'status': 'held',
        'releaseAt': '2026-11-22T20:00:00.000Z',
      },
    },
  );
  bool offline = false;

  List<RequestOptions> get posts =>
      requests.where((r) => r.method == 'POST').toList();

  StationRegistrarService service() {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            requests.add(o);
            if (offline) {
              h.reject(
                DioException.connectionError(requestOptions: o, reason: 'x'),
              );
              return;
            }
            final Answer answer = switch ((o.method, o.path)) {
              ('GET', '/public/network-status') => networkStatus,
              ('GET', '/weather/stations/mobile') => mobile,
              ('POST', '/station-registrar/requests') => post,
              ('GET', final p)
                  when p.startsWith('/station-registrar/requests/') =>
                status,
              _ => (599, null),
            };
            final response = Response<dynamic>(
              requestOptions: o,
              data: answer.$2,
              statusCode: answer.$1,
            );
            if (answer.$1 >= 400) {
              h.reject(
                DioException.badResponse(
                  statusCode: answer.$1,
                  requestOptions: o,
                  response: response,
                ),
              );
            } else {
              h.resolve(response);
            }
          },
        ),
      );
    return StationRegistrarService(apiClient: ApiClient(dio: dio));
  }
}

Map<String, Object> _active(List<String> features) => {
  'upgrades': {
    'status': 'ok',
    'active': [
      for (final f in features) {'feature': f, 'activationHeight': 100},
    ],
    'pending': <Object>[],
  },
};

Map<String, Object> _error(String code) => {
  'error': {'code': code, 'message': 'upstream text is never shown'},
};

void main() {
  group('featureActive', () {
    test(
      'only when the network lists station_registrar_key as active',
      () async {
        final b = _Backend();
        expect(await b.service().featureActive(), isTrue);
        for (final answer in <Answer>[
          (200, _active(['bond_admission_key'])),
          (
            200,
            {
              'upgrades': {'status': 'unavailable'},
            },
          ),
          (
            200,
            {
              'upgrades': {
                'status': 'ok',
                'active': <Object>[],
                'pending': [
                  {
                    'feature': 'station_registrar_key',
                    'activationHeight': 99999,
                  },
                ],
              },
            },
          ),
          (404, null),
          (200, 'not json'),
        ]) {
          b.networkStatus = answer;
          expect(await b.service().featureActive(), isFalse, reason: '$answer');
        }
      },
    );
  });

  group('status', () {
    test(
      'hidden (null) and no registrar read while the feature is inactive',
      () async {
        final b = _Backend()..networkStatus = (200, _active([]));
        expect(await b.service().status(syntheticStationId), isNull);
        expect(
          b.requests.where((r) => r.path.startsWith('/station-registrar')),
          isEmpty,
        );
      },
    );

    test('NOT_REQUESTED offers a request; a held answer parses', () async {
      final b = _Backend();
      expect(
        (await b.service().status(syntheticStationId))?.state,
        RegistrarState.notRequested,
      );
      expect(
        b.requests.last.path,
        '/station-registrar/requests/$syntheticStationId',
      );
      b.status = b.post;
      final held = await b.service().status(syntheticStationId);
      expect(held?.state, RegistrarState.held);
      expect(held?.releaseAt, DateTime.utc(2026, 11, 22, 20));
    });

    test('any other refusal or an unexpected answer hides the card', () async {
      final b = _Backend();
      for (final answer in <Answer>[
        (404, _error('REGISTRAR_DISABLED')),
        (503, _error('REGISTRAR_NOT_ACTIVE')),
        (
          200,
          {
            'ok': true,
            'data': {'stationId': syntheticStationId, 'status': 'weird'},
          },
        ),
        (
          200,
          {
            'ok': true,
            'data': {'stationId': 'mob-${'0' * 32}', 'status': 'held'},
          },
        ),
        (
          200,
          {
            'ok': true,
            'data': {'stationId': syntheticStationId, 'status': 'held'},
          },
        ),
      ]) {
        b.status = answer;
        expect(
          await b.service().status(syntheticStationId),
          isNull,
          reason: '$answer',
        );
      }
      expect(await b.service().status('ws-1'), isNull);
    });
  });

  group('request', () {
    test(
      'sends exactly the nine-field row with a valid ownership proof',
      () async {
        final b = _Backend();
        final session = (await SyntheticSigner().open())!;
        final result = await b.service().request(session);
        expect(result.state, RegistrarState.held);
        expect(b.posts, hasLength(1));
        final row = Map<String, Object?>.from(b.posts.single.data as Map);
        expect(row.keys.toSet(), {
          'station_id',
          'owner_address',
          'owner_pubkey',
          'owner_signature',
          'latitude',
          'longitude',
          'hardware_model',
          'provenance_class',
          'data_quality_tier',
        });
        expect(row['station_id'], syntheticStationId);
        expect(row['owner_address'], syntheticAddress);
        expect(row['latitude'], 37.7);
        expect(row['longitude'], -122.4);
        expect(row['hardware_model'], 'phone-barometer');
        expect(row['provenance_class'], 'real');
        expect(row['data_quality_tier'], 'unverified');
        // Exactly on the 0.1 degree grid, as the chain rule recomputes it.
        for (final k in ['latitude', 'longitude']) {
          final v = row[k]! as double;
          expect((v * 10).round() / 10, v);
        }
        Uint8List unhex(String h) => Uint8List.fromList([
          for (var i = 0; i < h.length; i += 2)
            int.parse(h.substring(i, i + 2), radix: 16),
        ]);
        final ok = await Ed25519().verify(
          stationOwnershipMessage(
            chainId: TransferSigningDomain.configured.chainId,
            networkId: TransferSigningDomain.configured.networkId,
            stationId: syntheticStationId,
            ownerAddress: syntheticAddress,
          ),
          signature: Signature(
            unhex(row['owner_signature']! as String),
            publicKey: SimplePublicKey(
              unhex(row['owner_pubkey']! as String),
              type: KeyPairType.ed25519,
            ),
          ),
        );
        expect(ok, isTrue);
      },
    );

    test(
      'only a backend registration still waiting can be requested',
      () async {
        for (final (answer, refusal) in <(Answer, RegistrarRefusal)>[
          ((404, _error('NOT_REGISTERED')), RegistrarRefusal.notRegistered),
          (
            (
              200,
              {
                'stationId': syntheticStationId,
                'status': 'submitted',
                'cell': {'latE1': 1, 'lonE1': 1},
              },
            ),
            RegistrarRefusal.notEligible,
          ),
          (
            (
              200,
              {
                'stationId': 'mob-${'0' * 32}',
                'status': 'db_only',
                'cell': {'latE1': 1, 'lonE1': 1},
              },
            ),
            RegistrarRefusal.notRegistered,
          ),
          (
            (
              200,
              {
                'stationId': syntheticStationId,
                'status': 'db_only',
                'cell': {'latE1': 1.5, 'lonE1': 1},
              },
            ),
            RegistrarRefusal.notEligible,
          ),
          (
            (
              200,
              {
                'stationId': syntheticStationId,
                'status': 'db_only',
                'cell': {'latE1': 901, 'lonE1': 1},
              },
            ),
            RegistrarRefusal.notEligible,
          ),
        ]) {
          final b = _Backend()..mobile = answer;
          final session = (await SyntheticSigner().open())!;
          await expectLater(
            b.service().request(session),
            throwsA(
              isA<RegistrarRequestException>().having(
                (e) => e.refusal,
                'refusal',
                refusal,
              ),
            ),
            reason: '$answer',
          );
          expect(b.posts, isEmpty);
        }
      },
    );

    test(
      'refusals map to fixed text, never upstream text, and are not retried',
      () async {
        for (final (code, refusal) in const [
          ('DAILY_PER_IP', RegistrarRefusal.limit),
          ('DAILY_PER_CELL', RegistrarRefusal.limit),
          ('DAILY_TOTAL', RegistrarRefusal.limit),
          ('ALREADY_REQUESTED', RegistrarRefusal.alreadyRequested),
          ('STATION_ALREADY_REGISTERED', RegistrarRefusal.alreadyRegistered),
          ('REGISTRATION_REFUSED', RegistrarRefusal.notEligible),
          ('REGISTRAR_CEILING', RegistrarRefusal.ceiling),
          ('REGISTRAR_STOPPED', RegistrarRefusal.closed),
          ('SOMETHING_NEW', RegistrarRefusal.closed),
        ]) {
          final b = _Backend()..post = (429, _error(code));
          final session = (await SyntheticSigner().open())!;
          await expectLater(
            b.service().request(session),
            throwsA(
              isA<RegistrarRequestException>().having(
                (e) => e.refusal,
                'refusal',
                refusal,
              ),
            ),
          );
          expect(b.posts, hasLength(1));
          expect(refusal.userMessage, isNot(contains('upstream')));
        }
        final offline = _Backend()..offline = true;
        await expectLater(
          offline.service().request((await SyntheticSigner().open())!),
          throwsA(
            isA<RegistrarRequestException>().having(
              (e) => e.refusal,
              'refusal',
              RegistrarRefusal.network,
            ),
          ),
        );
      },
    );

    test('a success that is not a hold is not reported as accepted', () async {
      final b = _Backend()
        ..post = (
          202,
          {
            'ok': true,
            'data': {'stationId': syntheticStationId, 'status': 'registered'},
          },
        );
      await expectLater(
        b.service().request((await SyntheticSigner().open())!),
        throwsA(isA<RegistrarRequestException>()),
      );
    });
  });
}
