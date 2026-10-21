import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/governance_vote_signing.dart';

import '../../../test_helpers/fakes.dart';

Map<String, dynamic> _requestBody(RequestOptions options) {
  final data = options.data;
  if (data is Map<String, dynamic>) return data;
  return <String, dynamic>{};
}

Future<GovernanceRepository> signedRepository(Dio dio) async {
  final keys = KeyManager(
    biometric: BiometricService(client: FakeLocalAuthClient()),
    storage: InMemoryKeyValueStorage(),
  );
  await keys.storeKeys(
    mnemonic: 'synthetic',
    privateKey: '07' * 32,
    address: '0x791026e25cc1ba461167ffb5c6dc095c284bd92c',
  );
  return GovernanceRepository(
    dio,
    signer: GovernanceVoteSigner(keyManager: keys, isForeground: () => true),
    ensureAuthenticated: () async => true,
  );
}

void main() {
  group('GovernanceRepository.getProposals', () {
    test('parses nested backend payload with proposals key', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: <String, dynamic>{
                  'success': true,
                  'count': 2,
                  'proposals': <Map<String, dynamic>>[
                    {
                      'id': 'prop-1',
                      'title': 'Upgrade Consensus',
                      'description': 'Reduce block time to 6s.',
                      'proposalType': 'platform_upgrade',
                      'status': 'active',
                      'votesFor': 80,
                      'votesAgainst': 15,
                      'votesAbstain': 5,
                    },
                    {
                      'id': 'prop-2',
                      'title': 'Treasury Q2 Spend',
                      'description': 'Allocate 200k WRF.',
                      'proposalType': 'treasury_spending',
                      'status': 'passed',
                      'votesFor': 60,
                      'votesAgainst': 5,
                      'votesAbstain': 0,
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

      final repository = await signedRepository(dio);
      final result = await repository.getProposals();

      result.fold((failure) => fail('Expected proposals, got $failure'), (
        proposals,
      ) {
        expect(proposals.length, 2);
        expect(proposals[0].id, 'prop-1');
        expect(proposals[0].title, 'Upgrade Consensus');
        expect(proposals[0].status, 'active');
        expect(proposals[0].votesFor, 80);
        expect(proposals[1].id, 'prop-2');
        expect(proposals[1].status, 'passed');
      });
    });

    test('parses flat data key fallback', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: <String, dynamic>{
                  'data': <Map<String, dynamic>>[
                    {
                      'id': 'prop-3',
                      'title': 'Deprecate PoW',
                      'description': 'Remove legacy PoW module.',
                      'status': 'active',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

      final repository = await signedRepository(dio);
      final result = await repository.getProposals();

      result.fold((failure) => fail('Expected proposals, got $failure'), (
        proposals,
      ) {
        expect(proposals.length, 1);
        expect(proposals[0].id, 'prop-3');
      });
    });

    test('returns empty list when no proposals field present', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: <String, dynamic>{'success': true},
              ),
            );
          },
        ),
      );

      final repository = await signedRepository(dio);
      final result = await repository.getProposals();

      result.fold(
        (failure) => fail('Expected empty list, got $failure'),
        (proposals) => expect(proposals, isEmpty),
      );
    });
  });

  group('GovernanceRepository.vote', () {
    test(
      'posts proposalId, voteType, and reason to correct endpoint',
      () async {
        String? capturedPath;
        Map<String, dynamic>? capturedBody;

        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedPath = options.path;
              capturedBody = _requestBody(options);
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: <String, dynamic>{'success': true},
                ),
              );
            },
          ),
        );

        final repository = await signedRepository(dio);
        final result = await repository.vote(
          proposalId: 'prop-42',
          voteType: 'FOR',
          reason: 'Great proposal',
        );

        result.fold((failure) => fail('Expected success, got $failure'), (_) {
          expect(capturedPath, contains('prop-42'));
          expect(capturedBody?['voteType'], 'FOR');
          expect(capturedBody?['reason'], 'Great proposal');
        });
      },
    );

    test('omits reason field when reason is null or empty', () async {
      Map<String, dynamic>? capturedBody;

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedBody = _requestBody(options);
            handler.resolve(
              Response(
                requestOptions: options,
                data: <String, dynamic>{'success': true},
              ),
            );
          },
        ),
      );

      final repository = await signedRepository(dio);
      await repository.vote(proposalId: 'prop-1', voteType: 'AGAINST');

      expect(capturedBody?.containsKey('reason'), isFalse);
    });
  });

  group('GovernanceRepository.getTreasuryInfo', () {
    test('parses nested treasury payloads', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: const <String, dynamic>{
                  'success': true,
                  'treasury': {
                    'balance': '1500 WRF',
                    'currency': 'WRF',
                    'lastUpdated': '2026-03-10T00:00:00Z',
                  },
                },
              ),
            );
          },
        ),
      );

      final repository = await signedRepository(dio);
      final result = await repository.getTreasuryInfo();
      result.fold((failure) => fail('Expected treasury info, got $failure'), (
        treasury,
      ) {
        expect(treasury['balance'], '1500');
        expect(treasury['currency'], 'WRF');
        expect(treasury['lastUpdated'], '2026-03-10T00:00:00Z');
      });
    });

    test('handles flat balance field without treasury wrapper', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: const <String, dynamic>{
                  'balance': '2000',
                  'currency': 'WRF',
                },
              ),
            );
          },
        ),
      );

      final repository = await signedRepository(dio);
      final result = await repository.getTreasuryInfo();
      result.fold(
        (failure) => fail('Expected treasury info, got $failure'),
        (treasury) => expect(treasury['balance'], '2000'),
      );
    });
  });
}
