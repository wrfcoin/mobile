import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/role_earnings_repository.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/providers/role_earnings_provider.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/leaderboard_screen.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/achievements_screen.dart';

import '../../../fixtures/role_earnings_fixture.dart';

class Script {
  final List<Object?> capabilities;
  int capsCalls = 0, boardCalls = 0, legacyCalls = 0, profileCalls = 0;
  Completer<void>? pause;
  late final ProviderContainer container;
  Script(this.capabilities) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          if (o.path == '/capabilities') {
            final n = capsCalls++;
            final answer =
                capabilities[n < capabilities.length
                    ? n
                    : capabilities.length - 1];
            if (pause != null) await pause!.future;
            if (answer == null) {
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.connectionError,
                ),
              );
            } else {
              h.resolve(
                Response(
                  requestOptions: o,
                  data: answer is String
                      ? {
                          'features': {
                            'earningsRead': {'status': answer},
                          },
                        }
                      : answer,
                ),
              );
            }
          } else if (o.path == '/earnings/leaderboard') {
            boardCalls++;
            h.resolve(Response(requestOptions: o, data: roleBoard('producer')));
          } else if (o.path == '/weather/leaderboard') {
            legacyCalls++;
            h.resolve(
              Response(
                requestOptions: o,
                data: jsonDecode(
                  File('test/fixtures/leaderboard_backend_1456.json')
                      .readAsStringSync(),
                ),
              ),
            );
          } else {
            profileCalls++;
            h.resolve(
              Response(requestOptions: o, data: roleFixture()['ownProfile']),
            );
          }
        },
      ),
    );
    container = ProviderContainer(
      overrides: [
        roleEarningsRepositoryProvider.overrideWithValue(
          RoleEarningsRepository(dio),
        ),
        gamificationRepositoryProvider.overrideWithValue(
          GamificationRepository(dio),
        ),
        ownEarningsAddressProvider.overrideWith((ref) async => 'synthetic-own'),
      ],
    );
  }
  Widget widget({bool profile = false}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: profile ? const AchievementsScreen() : const LeaderboardScreen(),
    ),
  );
}

void main() {
  testWidgets(
    'transient error stays UNKNOWN; Retry re-reads capabilities and enables board',
    (tester) async {
      final s = Script([null, 'configured']);
      addTearDown(s.container.dispose);
      await tester.pumpWidget(s.widget());
      await tester.pumpAndSettle();
      expect(find.text('Earnings unavailable right now'), findsOneWidget);
      expect(find.text('Block producers'), findsNothing);
      expect(s.legacyCalls, 0);
      expect(s.boardCalls, 0);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(s.capsCalls, 1);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Block producers'), findsOneWidget);
      expect(find.text('90071992.54741000 WRF'), findsOneWidget);
      expect(s.capsCalls, 2);
      expect(s.boardCalls, 1);
    },
  );
  testWidgets(
    'explicit OFF keeps role boards and own summary hidden without retry storm',
    (tester) async {
      final s = Script(['unavailable']);
      addTearDown(s.container.dispose);
      await tester.pumpWidget(s.widget(profile: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leaderboard'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Block producers'), findsNothing);
      expect(find.text('Your role payments · All time'), findsNothing);
      expect(s.capsCalls, 1);
      expect(s.boardCalls, 0);
      expect(s.profileCalls, 0);
      expect(s.legacyCalls, 1);
    },
  );
  testWidgets('pull to refresh UNKNOWN performs one fresh capability read', (
    tester,
  ) async {
    final s = Script([null, 'operational']);
    addTearDown(s.container.dispose);
    await tester.pumpWidget(s.widget());
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(s.capsCalls, 2);
    expect(s.boardCalls, 1);
    expect(find.text('Block producers'), findsOneWidget);
  });
  testWidgets(
    'repeat failure stays UNKNOWN and rapid Retry taps share a bounded read',
    (tester) async {
      final s = Script([null]);
      addTearDown(s.container.dispose);
      await tester.pumpWidget(s.widget());
      await tester.pumpAndSettle();
      s.pause = Completer<void>();
      // Invoke the same live button twice before the loading rebuild.
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Retry'),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(s.capsCalls, 2);
      s.pause!.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(s.capsCalls, 2);
      expect(s.boardCalls, 0);
      expect(s.legacyCalls, 0);
      expect(find.text('Retry'), findsOneWidget);
    },
  );
  testWidgets(
    'next entry retries cached UNKNOWN even if a shared consumer holds provider',
    (tester) async {
      final s = Script([null, 'configured']);
      addTearDown(s.container.dispose);
      final hold = s.container.listen(earningsReadProvider, (_, _) {});
      addTearDown(hold.close);
      await tester.pumpWidget(s.widget());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(s.capsCalls, 1);
      await tester.pumpWidget(s.widget());
      await tester.pumpAndSettle();
      expect(s.capsCalls, 2);
      expect(s.boardCalls, 1);
      expect(find.text('Block producers'), findsOneWidget);
    },
  );
  testWidgets(
    'shared Profile summary remains hidden on UNKNOWN and loads only after capability Retry',
    (tester) async {
      final s = Script([null, null, 'configured']);
      addTearDown(s.container.dispose);
      await tester.pumpWidget(s.widget(profile: true));
      await tester.pumpAndSettle();
      expect(find.text('Your role payments · All time'), findsNothing);
      expect(s.profileCalls, 0);
      expect(s.capsCalls, 1);
      await tester.tap(find.text('Leaderboard'));
      await tester.pumpAndSettle();
      expect(s.capsCalls, 2); // First board entry retries cached UNKNOWN once.
      expect(s.profileCalls, 0);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(s.capsCalls, 3);
      expect(s.boardCalls, 1);
      await tester.tap(find.text('Achievements'));
      await tester.pumpAndSettle();
      expect(find.text('Your role payments · All time'), findsOneWidget);
      expect(s.profileCalls, 1);
    },
  );
  for (final body in <Object>[
    {},
    {
      'features': {
        'earningsRead': {'status': null},
      },
    },
    <Object>[],
  ]) {
    testWidgets(
      'malformed capabilities stay UNKNOWN and never fetch rows: $body',
      (tester) async {
        final s = Script([body]);
        addTearDown(s.container.dispose);
        await tester.pumpWidget(s.widget());
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsOneWidget);
        expect(s.capsCalls, 1);
        expect(s.boardCalls, 0);
        expect(s.legacyCalls, 0);
      },
    );
  }
}
