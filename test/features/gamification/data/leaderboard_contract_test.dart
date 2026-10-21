import 'dart:convert';

import 'package:wrfcoin_mobile/features/gamification/data/models/role_earnings_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/role_earnings_repository.dart';

import '../../../fixtures/role_earnings_fixture.dart';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';

Map<String, dynamic> fixture() => jsonDecode(
  File('test/fixtures/leaderboard_backend_1456.json').readAsStringSync(),
) as Map<String, dynamic>;

void main() {
  for (final role in EarningsRole.values) {
    for (final period in EarningsPeriod.values) {
      test('B2 exact Dio URI ${role.name}/${period.wire}', () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              expect(o.path, '/earnings/leaderboard');
              expect(
                o.uri.query,
                'role=${role.name}&period=${period.wire}&limit=30',
              );
              final body = roleBoard(role.name)
                ..['requestedScope'] = period.wire;
              if (body['status'] == 'available') {
                body['effectiveScope'] = period.wire;
                body['window']['from'] = period == EarningsPeriod.all
                    ? null
                    : period == EarningsPeriod.sevenDays
                    ? '2026-10-04T12:00:00.000001Z'
                    : '2026-09-11T12:00:00.000001Z';
              }
              h.resolve(Response(requestOptions: o, data: body));
            },
          ),
        );
        final board = await RoleEarningsRepository(dio)
            .leaderboard(role, period);
        expect(board.role, role);
      });
    }
  }
  for (final status in ['unavailable', 'simulated', 'reachable', 'loading']) {
    test('earningsRead $status hides roles', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            expect(o.path, '/capabilities');
            h.resolve(
              Response(
                requestOptions: o,
                data: {
                  'features': {
                    'earningsRead': {'status': status},
                  },
                },
              ),
            );
          },
        ),
      );
      expect(await RoleEarningsRepository(dio).enabled(), isFalse);
    });
  }

  Future<bool> accepts(
    Map<String, dynamic> body, {
    void Function(RequestOptions)? request,
  }) async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          request?.call(o);
          h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
        },
      ),
    );
    return (await GamificationRepository(dio).getLeaderboard()).isRight();
  }

  test(
    'public edge query is metric, period, limit in that order, capped at 30',
    () async {
      expect(
        await accepts(
          fixture(),
          request: (o) {
            expect(o.uri.query, 'metric=earnings&period=7d&limit=30');
          },
        ),
        isTrue,
      );
    },
  );

  test(
    'backend #1456 paid row is accepted without using numeric value',
    () async {
      final dio = Dio();
      final body = fixture();
      (body['entries'] as List).single['value'] = -1;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) =>
              h.resolve(Response(requestOptions: o, data: body)),
        ),
      );
      final rows = (await GamificationRepository(
        dio,
      ).getLeaderboard()).getOrElse((f) => fail('$f'));
      expect(rows.single.score, '15.24000000');
    },
  );

  for (final field in [
    'denomination',
    'baseUnitDecimals',
    'baseUnitsPerUnit',
    'available',
    'fields',
  ]) {
    test(
      'missing amountUnits.$field is unavailable, even with valid rows',
      () async {
        final body = fixture();
        (body['amountUnits'] as Map).remove(field);
        expect(await accepts(body), isFalse);
      },
    );
  }
  for (final change in <String, Object>{
    'denomination': 'OTHER',
    'baseUnitDecimals': 18,
    'baseUnitsPerUnit': '1000',
    'available': false,
    'fields': {'entries[].earningsBaseUnits': 'display_units'},
  }.entries) {
    test('incompatible amountUnits.${change.key} cannot display WRF', () async {
      final body = fixture();
      (body['amountUnits'] as Map)[change.key] = change.value;
      expect(await accepts(body), isFalse);
    });
  }
  test(
    'missing metadata or failed success cannot become an empty board',
    () async {
      for (final field in ['success', 'earningsScope', 'amountUnits']) {
        final body = fixture()..['entries'] = [];
        body.remove(field);
        expect(await accepts(body), isFalse);
      }
      expect(await accepts(fixture()..['success'] = false), isFalse);
    },
  );
}
