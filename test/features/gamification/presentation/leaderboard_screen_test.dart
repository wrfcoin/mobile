import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/providers/role_earnings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/leaderboard_screen.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/achievements_screen.dart';

/// Drives the real repository through a scripted Dio so the screen is tested
/// against the actual wire shape (backend#1457).
Widget _screen(
  List<(int, Object)> script, {
  List<int>? calls,
  bool profile = false,
}) {
  final dio = Dio();
  var n = 0;
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final (status, body) =
            script[n < script.length ? n : script.length - 1];
        n++;
        calls?.add(status);
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
  return ProviderScope(
    overrides: [
      earningsReadProvider.overrideWith((ref) async => false),
      gamificationRepositoryProvider.overrideWithValue(
        GamificationRepository(dio),
      ),
    ],
    child: MaterialApp(
      home: profile ? const AchievementsScreen() : const LeaderboardScreen(),
    ),
  );
}

final _board = <String, dynamic>{
  ..._metadata,
  'success': true,
  'entries': [
    {
      'rank': 1,
      'displayName': 'Alpha',
      'walletAddress': '0xaaaa…aaaa',
      'isYou': false,
      'earningsBaseUnits': '250000000',
    },
    {
      'rank': 2,
      'displayName': 'Me',
      'walletAddress': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'isYou': true,
      'earningsBaseUnits': '1',
    },
  ],
};

const _unavailable = <String, dynamic>{
  'success': false,
  'unavailable': ['earnings'],
  'entries': <dynamic>[],
};

final _metadata = (jsonDecode(
  File('test/fixtures/leaderboard_backend_1456.json').readAsStringSync(),
) as Map<String, dynamic>)..remove('entries');

void main() {
  for (final scenario in [
    (_board, 'Alpha'),
    ({..._metadata, 'entries': <dynamic>[]}, 'No one has earned yet'),
    (_unavailable, 'Earnings unavailable right now'),
  ]) {
    testWidgets('Profile leaderboard: ${scenario.$2}', (tester) async {
      await tester.pumpWidget(_screen([(200, scenario.$1)], profile: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leaderboard'));
      await tester.pumpAndSettle();
      expect(find.text(scenario.$2), findsOneWidget);
    });
  }

  testWidgets(
    'renders ranked earnings rows, address as served, own row marked',
    (tester) async {
      await tester.pumpWidget(_screen([(200, _board)]));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('2.50000000'), findsOneWidget);
      expect(find.text('0xaaaa…aaaa'), findsOneWidget);
      expect(find.text('0.00000001'), findsOneWidget);
      expect(
        find.text('0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        findsOneWidget,
      );
      expect(find.text('You'), findsOneWidget);
      expect(find.textContaining('earned yet'), findsNothing);
    },
  );

  testWidgets('genuine empty 200 shows the nobody-earned-yet copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen([
        (200, {..._metadata, 'entries': <dynamic>[]}),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('No one has earned yet'), findsOneWidget);
    expect(find.text('Earnings unavailable right now'), findsNothing);
  });

  testWidgets('503 shows unavailable + Retry, never the empty copy', (
    tester,
  ) async {
    await tester.pumpWidget(_screen([(503, _unavailable)]));
    await tester.pumpAndSettle();
    expect(find.text('Earnings unavailable right now'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No one has earned yet'), findsNothing);
  });

  testWidgets('other failures also never show the empty copy', (tester) async {
    await tester.pumpWidget(
      _screen([
        (500, {'error': 'x'}),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No one has earned yet'), findsNothing);
  });

  testWidgets('Retry after 503 loads the board', (tester) async {
    await tester.pumpWidget(_screen([(503, _unavailable), (200, _board)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Earnings unavailable right now'), findsNothing);
  });
}
