import 'package:dio/dio.dart';

import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/widgets/role_earnings_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/role_earnings_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/role_earnings_repository.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';

import 'dart:convert';
import 'dart:io';

import 'package:wrfcoin_mobile/features/gamification/presentation/providers/role_earnings_provider.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/leaderboard_screen.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/achievements_screen.dart';

import '../../../fixtures/role_earnings_fixture.dart';
import '../../../fixtures/weather_earnings_fixture.dart';

Widget screen({
  bool profile = false,
  bool failed = false,
  bool own = true,
  bool empty = false,
}) {
  final dio = Dio();
  var retry = failed;
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        if (o.path.contains('/operators/')) {
          final body = roleFixture()['ownProfile'];
          body['profile']['isYou'] = own;
          h.resolve(Response(requestOptions: o, data: body));
          return;
        }
        if (retry) {
          retry = false;
          h.reject(DioException(requestOptions: o));
          return;
        }
        if (o.path == '/weather/leaderboard') {
          final body = weatherBoard(
            period: o.queryParameters['period'] as String,
          );
          if (empty) body['entries'] = [];
          h.resolve(Response(requestOptions: o, data: body));
          return;
        }
        final role = o.queryParameters['role'] as String;
        final body = roleBoard(role);
        if (empty) body['rows'] = [];
        h.resolve(Response(requestOptions: o, data: body));
      },
    ),
  );
  return ProviderScope(
    overrides: [
      earningsReadProvider.overrideWith((ref) async => true),
      ownEarningsAddressProvider.overrideWith(
        (ref) async => '0x0000000000000000000000000000000000000001',
      ),
      roleEarningsRepositoryProvider.overrideWithValue(
        RoleEarningsRepository(dio),
      ),
    ],
    child: MaterialApp(
      home: profile ? const AchievementsScreen() : const LeaderboardScreen(),
    ),
  );
}

void main() {
  testWidgets(
    'own summary clears across identity refresh and hides old amounts',
    (tester) async {
      final address = StateProvider<String?>((ref) => 'synthetic-first');
      final pending = Completer<Response<dynamic>>();
      var profileReads = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            if (o.path == '/weather/leaderboard') {
              h.resolve(Response(requestOptions: o, data: weatherBoard()));
            } else if (o.path == '/earnings/leaderboard') {
              h.resolve(
                Response(
                  requestOptions: o,
                  data: roleBoard(o.queryParameters['role'] as String),
                ),
              );
            } else if (++profileReads == 1) {
              h.resolve(
                Response(requestOptions: o, data: roleFixture()['ownProfile']),
              );
            } else {
              final response = await pending.future;
              h.resolve(Response(requestOptions: o, data: response.data));
            }
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [
          earningsReadProvider.overrideWith((ref) async => true),
          ownEarningsAddressProvider.overrideWith(
            (ref) async => ref.watch(address),
          ),
          roleEarningsRepositoryProvider.overrideWithValue(
            RoleEarningsRepository(dio),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: OwnRoleEarningsSummary()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('90071992.54741000 WRF'), findsNWidgets(2));
      container.read(address.notifier).state = 'synthetic-second';
      await tester.pump();
      await tester.pump();
      expect(find.text('90071992.54741000 WRF'), findsNothing);
      final body = roleFixture()['ownProfile'];
      body['profile']['isYou'] = false;
      pending.complete(Response(requestOptions: RequestOptions(), data: body));
      await tester.pumpAndSettle();
      expect(find.text('Your role payments · All time'), findsNothing);
    },
  );

  testWidgets(
    'real capability OFF hides role controls and own summary; retains legacy board',
    (tester) async {
      final paths = <String>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            paths.add(o.path);
            final body = o.path == '/capabilities'
                ? {
                    'features': {
                      'earningsRead': {'status': 'unavailable'},
                    },
                  }
                : jsonDecode(
                    File('test/fixtures/leaderboard_backend_1456.json')
                        .readAsStringSync(),
                  );
            h.resolve(Response(requestOptions: o, data: body));
          },
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleEarningsRepositoryProvider.overrideWithValue(
              RoleEarningsRepository(dio),
            ),
            gamificationRepositoryProvider.overrideWithValue(
              GamificationRepository(dio),
            ),
          ],
          child: const MaterialApp(home: AchievementsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leaderboard'));
      await tester.pumpAndSettle();
      expect(find.text('Block producers'), findsNothing);
      expect(find.text('Your role payments · All time'), findsNothing);
      expect(paths, ['/capabilities', '/weather/leaderboard']);
    },
  );

  testWidgets(
    'standalone role states, exact units, coverage and anonymous labels',
    (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.text('90071992.54741000 WRF'), findsOneWidget);
      expect(find.text('0x0000…0001 · You'), findsOneWidget);
      expect(find.textContaining('Through height 4'), findsOneWidget);
      expect(find.textContaining('N5'), findsNothing);
      for (final role in [
        'Weather data',
        'Oracles & attesters',
        'Nodes',
        'Forecasting',
      ]) {
        await tester.ensureVisible(find.text(role));
        await tester.tap(find.text(role));
        await tester.pumpAndSettle();
        if (role == 'Nodes') {
          expect(find.text(kNodePaymentsNotice), findsOneWidget);
          expect(find.textContaining('not implemented'), findsNothing);
        } else if (role == 'Weather data') {
          expect(find.text('1887.95124509 WRF'), findsOneWidget);
          expect(find.text('Earnings unavailable right now'), findsNothing);
        } else if (role == 'Forecasting') {
          expect(find.text('Earnings unavailable right now'), findsOneWidget);
          expect(find.text('No forecast payments observed'), findsNothing);
          expect(find.text('90071992.54741000 WRF'), findsNothing);
        } else {
          expect(find.text('90071992.54741000 WRF'), findsOneWidget);
        }
      }
    },
  );
  testWidgets('available empty is distinct; no amount fabricated', (
    tester,
  ) async {
    await tester.pumpWidget(screen(empty: true));
    await tester.pumpAndSettle();
    expect(find.text('No payments observed for this period'), findsOneWidget);
    expect(find.text('Earnings unavailable right now'), findsNothing);
  });
  testWidgets('Retry after failed read renders real board', (tester) async {
    await tester.pumpWidget(screen(failed: true));
    await tester.pumpAndSettle();
    expect(find.text('Earnings unavailable right now'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('90071992.54741000 WRF'), findsOneWidget);
  });
  testWidgets('Profile has authenticated own summary and embedded role board', (
    tester,
  ) async {
    await tester.pumpWidget(screen(profile: true));
    await tester.pumpAndSettle();
    expect(find.text('Your role payments · All time'), findsOneWidget);
    expect(find.text('90071992.54741000 WRF'), findsNWidgets(2));
    expect(find.text(kNodePaymentsNotice), findsOneWidget);
    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();
    expect(find.text('90071992.54741000 WRF'), findsOneWidget);
  });
  testWidgets('Profile with unverified ownership withholds role amounts', (
    tester,
  ) async {
    await tester.pumpWidget(screen(profile: true, own: false));
    await tester.pumpAndSettle();
    expect(find.text('Your role earnings are unavailable'), findsOneWidget);
    expect(find.text('Your role payments · All time'), findsNothing);
    expect(find.text('90071992.54741000 WRF'), findsNothing);
  });
}
