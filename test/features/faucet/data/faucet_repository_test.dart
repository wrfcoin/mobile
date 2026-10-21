import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/faucet/data/datasources/faucet_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/faucet/data/repositories/faucet_repository.dart';

/// Builds a Dio whose interceptor resolves or rejects every request with a
/// canned response, so the repository can be exercised without a network.
Dio _dioReturning({
  required int statusCode,
  required Object? data,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final response = Response<dynamic>(
          requestOptions: options,
          statusCode: statusCode,
          data: data,
        );
        if (statusCode >= 200 && statusCode < 300) {
          handler.resolve(response);
        } else {
          handler.reject(
            DioException(
              requestOptions: options,
              response: response,
              type: DioExceptionType.badResponse,
            ),
          );
        }
      },
    ),
  );
  return dio;
}

void main() {
  group('FaucetRepository', () {
    test('requestChallenge parses challengeId and question', () async {
      final repo = FaucetRepository(
        FaucetRemoteDataSource(
          _dioReturning(
            statusCode: 200,
            data: const {'challengeId': 'abc123', 'question': 'What is 2 + 3?'},
          ),
        ),
      );

      final result = await repo.requestChallenge();

      result.fold(
        (failure) => fail('Expected a challenge, got $failure'),
        (challenge) {
          expect(challenge.challengeId, 'abc123');
          expect(challenge.question, 'What is 2 + 3?');
        },
      );
    });

    test('claim parses txHash, amount and balance on success', () async {
      final repo = FaucetRepository(
        FaucetRemoteDataSource(
          _dioReturning(
            statusCode: 200,
            data: const {
              'txHash': '0xdeadbeef',
              'amount': '100',
              'balance': '100',
            },
          ),
        ),
      );

      final result = await repo.claim(
        walletAddress: '0x1111111111111111111111111111111111111111',
        challengeId: 'abc123',
        answer: 5,
      );

      result.fold(
        (failure) => fail('Expected a claim result, got $failure'),
        (claim) {
          expect(claim.txHash, '0xdeadbeef');
          expect(claim.amount, '100');
          expect(claim.balance, '100');
        },
      );
    });

    test('claim surfaces backend 429 cooldown message verbatim', () async {
      final repo = FaucetRepository(
        FaucetRemoteDataSource(
          _dioReturning(
            statusCode: 429,
            data: const {
              'error': {
                'code': 'ALREADY_CLAIMED',
                'message':
                    'This address has already claimed tokens within the last 24 hours',
              },
            },
          ),
        ),
      );

      final result = await repo.claim(
        walletAddress: '0x1111111111111111111111111111111111111111',
        challengeId: 'abc123',
        answer: 5,
      );

      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.statusCode, 429);
          expect(
            failure.message,
            'This address has already claimed tokens within the last 24 hours',
          );
        },
        (_) => fail('Expected a cooldown failure'),
      );
    });

    test('claim surfaces backend captcha failure message', () async {
      final repo = FaucetRepository(
        FaucetRemoteDataSource(
          _dioReturning(
            statusCode: 400,
            data: const {
              'error': {
                'code': 'CAPTCHA_FAILED',
                'message': 'Incorrect captcha answer',
              },
            },
          ),
        ),
      );

      final result = await repo.claim(
        walletAddress: '0x1111111111111111111111111111111111111111',
        challengeId: 'abc123',
        answer: 99,
      );

      result.fold(
        (failure) => expect(failure.message, 'Incorrect captcha answer'),
        (_) => fail('Expected a captcha failure'),
      );
    });

    test('malformed challenge payload becomes a ServerFailure', () async {
      final repo = FaucetRepository(
        FaucetRemoteDataSource(
          _dioReturning(statusCode: 200, data: const <dynamic>['nope']),
        ),
      );

      final result = await repo.requestChallenge();

      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, 'Expected faucet API response to be an object.');
        },
        (_) => fail('Expected a ServerFailure for a non-object payload'),
      );
    });
  });
}
