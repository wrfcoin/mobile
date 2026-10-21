import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';

final _metadata = (jsonDecode(
  File('test/fixtures/leaderboard_backend_1456.json').readAsStringSync(),
) as Map<String, dynamic>)..remove('entries');

void main() {
  group('GamificationRepository', () {
    late Dio dio;
    late GamificationRepository repository;

    setUp(() {
      dio = Dio();
      repository = GamificationRepository(dio);
    });

    test('maps wrapped achievement progress payloads into UI models', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: const <String, dynamic>{
                  'success': true,
                  'data': [
                    {
                      'achievementId': 'weather_collector',
                      'progress': 75,
                      'completed': false,
                      'metadata': {'submissions': 75},
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

      final result = await repository.getAchievements('wrf1wallet');

      result.fold((failure) => fail('Expected achievements, got $failure'), (
        achievements,
      ) {
        expect(achievements, hasLength(1));
        expect(achievements.single.id, 'weather_collector');
        expect(achievements.single.name, 'Weather Collector');
        expect(achievements.single.description, 'Submissions: 75');
        expect(achievements.single.progress, 0.75);
        expect(achievements.single.earned, isFalse);
      });
    });

    group('getLeaderboard (earnings board, #409)', () {
      void respond(int status, Object body) {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              final res = Response(
                requestOptions: options,
                statusCode: status,
                data: body,
              );
              if (status >= 400) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: res,
                    type: DioExceptionType.badResponse,
                  ),
                );
              } else {
                handler.resolve(res);
              }
            },
          ),
        );
      }

      test('reads entries[] and formats earningsBaseUnits exactly', () async {
        respond(200, {
          ..._metadata,
          'success': true,
          'earningsScope': 'lifetime',
          'entries': [
            {
              'rank': 1,
              'displayName': 'Alpha',
              'walletAddress': '0xaaaa…aaaa',
              'isYou': false,
              'earningsBaseUnits': '1234567890123',
              'earningsWrf': '12345.67890123',
            },
            {
              'rank': 2,
              'displayName': 'Me',
              'walletAddress': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              'isYou': true,
              'earningsBaseUnits': '5',
              'earningsWrf': '0.00000005',
            },
          ],
        });
        final result = await repository.getLeaderboard();
        final entries = result.getOrElse((f) => fail('got $f'));
        expect(entries, hasLength(2));
        expect(entries[0].name, 'Alpha');
        expect(entries[0].score, '12345.67890123');
        expect(entries[1].isYou, isTrue);
        expect(entries[1].score, '0.00000005');
      });

      test('genuine empty 200 is Right([])', () async {
        respond(200, {..._metadata, 'success': true, 'entries': <dynamic>[]});
        final result = await repository.getLeaderboard();
        expect(result.getOrElse((f) => fail('got $f')), isEmpty);
      });

      test(
        '503 unavailable:[earnings] is a failure, not an empty list',
        () async {
          respond(503, {
            'success': false,
            'unavailable': ['earnings'],
            'entries': <dynamic>[],
          });
          final result = await repository.getLeaderboard();
          result.fold((f) {
            expect(f, isA<NotAvailableFailure>());
            expect((f as NotAvailableFailure).detail, 'earnings');
          }, (e) => fail('Expected failure, got $e'));
        },
      );

      test(
        '200 carrying unavailable is a failure, never partial rows',
        () async {
          respond(200, {
            ..._metadata,
            'success': true,
            'unavailable': ['earnings'],
            'entries': [
              {'rank': 1, 'displayName': 'A', 'earningsBaseUnits': '1'},
            ],
          });
          final result = await repository.getLeaderboard();
          expect(result.isLeft(), isTrue);
        },
      );

      test('a row with an unprovable amount fails the whole board', () async {
        respond(200, {
          ..._metadata,
          'success': true,
          'entries': [
            {'rank': 1, 'displayName': 'A', 'earningsBaseUnits': '1'},
            {'rank': 2, 'displayName': 'B', 'earningsBaseUnits': null},
          ],
        });
        final result = await repository.getLeaderboard();
        expect(result.isLeft(), isTrue);
      });

      test(
        'a 200 that is not a Map with a List entries is unavailable',
        () async {
          final bodies = <Object?>[
            <String, dynamic>{},
            {'success': true},
            'oops',
            <dynamic>[],
            {'entries': null},
            {
              'entries': {'a': 1},
            },
          ];
          for (final body in bodies) {
            final d = Dio();
            d.interceptors.add(
              InterceptorsWrapper(
                onRequest: (o, h) => h.resolve(
                  Response(requestOptions: o, statusCode: 200, data: body),
                ),
              ),
            );
            final result = await GamificationRepository(d).getLeaderboard();
            result.fold((f) {
              expect(f, isA<NotAvailableFailure>(), reason: '$body');
              expect((f as NotAvailableFailure).detail, 'earnings');
            }, (e) => fail('body $body gave $e'));
          }
        },
      );

      test('a row missing earningsBaseUnits fails the whole board', () async {
        respond(200, {
          ..._metadata,
          'entries': [
            {'rank': 1, 'displayName': 'A', 'earningsBaseUnits': '5'},
            {'rank': 2, 'displayName': 'B', 'value': 3},
          ],
        });
        final result = await repository.getLeaderboard();
        result.fold((f) {
          expect(f, isA<NotAvailableFailure>());
          expect((f as NotAvailableFailure).detail, 'earnings');
        }, (e) => fail('got $e'));
      });

      test('a non-numeric rank is unavailable, not ServerFailure', () async {
        respond(200, {
          ..._metadata,
          'entries': [
            {'rank': 'first', 'displayName': 'A', 'earningsBaseUnits': '5'},
          ],
        });
        final result = await repository.getLeaderboard();
        result.fold(
          (f) => expect(f, isA<NotAvailableFailure>()),
          (e) => fail('got $e'),
        );
      });

      test('plain 500 is a failure', () async {
        respond(500, {'error': 'x'});
        expect((await repository.getLeaderboard()).isLeft(), isTrue);
      });
    });

    test('prefers nested achievement ids over nullable wrapper ids', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: const <String, dynamic>{
                  'success': true,
                  'data': [
                    {
                      'id': null,
                      'progress': 100,
                      'completed': true,
                      'achievement': {
                        'id': 'inner-achievement-id',
                        'achievementId': 'governance_participant',
                        'name': 'Governance Participant',
                        'tier': 'silver',
                      },
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

      final result = await repository.getAchievements('wrf1wallet');

      result.fold(
        (failure) =>
            fail('Expected nested achievement id to win, got $failure'),
        (achievements) {
          expect(achievements, hasLength(1));
          expect(achievements.single.id, 'inner-achievement-id');
          expect(achievements.single.name, 'Governance Participant');
          expect(achievements.single.tier, 'silver');
          expect(achievements.single.earned, isTrue);
        },
      );
    });
  });
}
