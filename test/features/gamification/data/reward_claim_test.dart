import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';

void main() {
  group('GamificationRepository.claimReward', () {
    late Dio dio;
    late GamificationRepository repository;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
      repository = GamificationRepository(dio);
    });

    test('POSTs to correct endpoint with userId and achievementId', () async {
      String? capturedPath;
      Map<String, dynamic>? capturedBody;

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedPath = options.path;
            capturedBody = options.data as Map<String, dynamic>?;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'rewardId': 'reward-001',
                  'wrfAmount': 10.0,
                  'txHash': '0xabc123',
                },
              ),
            );
          },
        ),
      );

      await repository.claimReward('user-001', 'achievement-99');

      expect(capturedPath, equals(ApiConstants.claimReward('achievement-99')));
      expect(capturedBody?['userId'], equals('user-001'));
      expect(capturedBody?['achievementId'], equals('achievement-99'));
    });

    test(
      'maps success response to RewardResult with wrfAmount and txHash',
      () async {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'rewardId': 'r-42',
                    'wrfAmount': 5.5,
                    'txHash': '0xdeadbeef',
                  },
                ),
              );
            },
          ),
        );

        final result = await repository.claimReward('user-1', 'ach-1');

        expect(result.isRight(), isTrue);
        result.fold((_) => fail('Expected Right'), (reward) {
          expect(reward.alreadyClaimed, isFalse);
          expect(reward.rewardId, equals('r-42'));
          expect(reward.wrfAmount, equals(5.5));
          expect(reward.txHash, equals('0xdeadbeef'));
        });
      },
    );

    test('full settled repeat keeps reward and settlement transaction', () async {
      // Backend ece94c9d rewards.ts:766-793 +
      // reward-payout-settlement.ts:130-140 (already_processed, gate OFF).
      // Ledger values follow rewards-claim.test.ts:169-173.
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{
                'success': true,
                'alreadyClaimed': true,
                'reward': {
                  'id': 100,
                  'userId': 1,
                  'contributorType': 'achievement',
                  'amount': 50,
                  'metadata': {
                    'achievementId': 'first-report',
                    'achievementRowId': 7,
                    'onChain': true,
                    'settlement': 'settled',
                    'claimId': 'ach:v1:1:first-report',
                    'address': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                    'amountBaseUnits': '5000000000',
                  },
                },
                'settlement': {
                  'state': 'settled',
                  'status': 'already_processed',
                  'txHash': '0xtx',
                  'onChain': true,
                  'note': null,
                  'terminal': true,
                  'attempts': 2,
                },
                'message':
                    'Reward of 50 WRF for "First report" has settled on-chain.',
              },
            ),
          ),
        ),
      );

      final result = await repository.claimReward('user-1', 'first-report');
      result.fold((_) => fail('Expected a settled repeat'), (reward) {
        expect(reward.rewardId, '100');
        expect(reward.wrfAmount, 50.0);
        expect(reward.txHash, '0xtx');
        expect(reward.alreadyClaimed, isTrue);
      });
    });

    test('settled acknowledgement carries no new reward', () async {
      // Backend ece94c9d: rewards.ts:694 and
      // rewards-signed-payout.test.ts:375 (exact response body).
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{
                'success': true,
                'alreadyClaimed': true,
                'settlement': {'state': 'settled', 'terminal': true},
              },
            ),
          ),
        ),
      );

      final result = await repository.claimReward('user-1', 'ach-1');
      expect(result.isRight(), isTrue);
      result.fold((_) => fail('Expected an acknowledgement'), (reward) {
        expect(reward.alreadyClaimed, isTrue);
        expect(reward.rewardId, isNull);
        expect(reward.wrfAmount, isNull);
        expect(reward.txHash, isNull);
      });
    });

    test(
      'normal reward envelope preserves ID, amount and transaction',
      () async {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'success': true,
                  'reward': {'id': 42, 'amount': '5.5', 'txHash': '0xtest'},
                },
              ),
            ),
          ),
        );
        final result = await repository.claimReward('user-1', 'ach-1');
        result.fold((_) => fail('Expected a normal reward'), (reward) {
          expect(reward.alreadyClaimed, isFalse);
          expect(reward.rewardId, '42');
          expect(reward.wrfAmount, 5.5);
          expect(reward.txHash, '0xtest');
        });
      },
    );

    test('unwraps "data" envelope in success response', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'success': true,
                  'data': <String, dynamic>{
                    'rewardId': 'wrapped-r',
                    'wrfAmount': 3.0,
                  },
                },
              ),
            );
          },
        ),
      );

      final result = await repository.claimReward('u', 'a');
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (reward) => expect(reward.wrfAmount, equals(3.0)),
      );
    });

    test('returns Left(Failure) on DioException (4xx)', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 400,
                  data: <String, dynamic>{'message': 'Already claimed'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final result = await repository.claimReward('u', 'a');
      expect(result.isLeft(), isTrue);
    });

    test('returns Left(Failure) on network error', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );

      final result = await repository.claimReward('u', 'a');
      expect(result.isLeft(), isTrue);
    });
  });

  group('GamificationRepository.getRewardHistory', () {
    late Dio dio;
    late GamificationRepository repository;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
      repository = GamificationRepository(dio);
    });

    test('GETs /api/v1/rewards/history with userId query param', () async {
      String? capturedPath;
      Map<String, dynamic>? capturedQuery;

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedPath = options.path;
            capturedQuery = options.queryParameters;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <dynamic>[
                  <String, dynamic>{
                    'achievementId': 'ach-1',
                    'wrfAmount': 2.0,
                    'claimedAt': '2026-01-01T00:00:00Z',
                  },
                ],
              ),
            );
          },
        ),
      );

      await repository.getRewardHistory('user-xyz');

      expect(capturedPath, equals(ApiConstants.rewardHistory));
      expect(capturedQuery?['userId'], equals('user-xyz'));
    });

    test('maps history response to RewardHistoryEntry list', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <dynamic>[
                  <String, dynamic>{
                    'achievementId': 'ach-weather',
                    'wrfAmount': 7.5,
                    'claimedAt': '2026-03-15T10:30:00Z',
                    'txHash': '0x111',
                  },
                ],
              ),
            );
          },
        ),
      );

      final result = await repository.getRewardHistory('u');
      expect(result.isRight(), isTrue);
      result.fold((_) => fail('Expected Right'), (entries) {
        expect(entries.length, equals(1));
        expect(entries.first.achievementId, equals('ach-weather'));
        expect(entries.first.wrfAmount, equals(7.5));
        expect(entries.first.txHash, equals('0x111'));
      });
    });
  });
}
