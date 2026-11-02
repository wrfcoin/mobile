import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/role_earnings_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/role_earnings_repository.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/providers/role_earnings_provider.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/leaderboard_screen.dart';

import '../../../fixtures/role_earnings_fixture.dart';
import '../../../fixtures/weather_earnings_fixture.dart';

Dio dioWith(List<Uri> seen, Map<String, dynamic> Function(String) weather) {
  final dio = Dio(BaseOptions(baseUrl: 'https://wrfcoin.test/api'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        seen.add(o.uri);
        if (o.path == '/weather/leaderboard') {
          h.resolve(
            Response(
              requestOptions: o,
              data: weather(o.queryParameters['period'] as String),
            ),
          );
          return;
        }
        h.resolve(
          Response(
            requestOptions: o,
            data: roleBoard(o.queryParameters['role'] as String),
          ),
        );
      },
    ),
  );
  return dio;
}

Widget app(Dio dio) => ProviderScope(
  overrides: [
    earningsReadProvider.overrideWith((ref) async => true),
    roleEarningsRepositoryProvider.overrideWithValue(
      RoleEarningsRepository(dio),
    ),
  ],
  child: const MaterialApp(home: LeaderboardScreen()),
);

Future<void> openWeatherTab(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Weather data'));
  await tester.pumpAndSettle();
}

void main() {
  group('weather board contract', () {
    for (final period in EarningsPeriod.values) {
      test('exact edge query for ${period.wire}', () async {
        final seen = <Uri>[];
        final board = await RoleEarningsRepository(
          dioWith(seen, (p) => weatherBoard(period: p)),
        ).leaderboard(EarningsRole.contribution, period);
        expect(seen.single.path, '/api/weather/leaderboard');
        expect(
          seen.single.query,
          'metric=earnings&period=${period.wire}&limit=30',
        );
        expect(board.lifetimeAmounts, isTrue);
        expect(board.rows.map((r) => r.amount), [
          '1887.95124509',
          '1215.47812500',
          '4.52812500',
        ]);
      });
    }

    test('the server-marked own row keeps its full address', () {
      final board = RoleLeaderboard.parseWeather(
        weatherBoard(ownRow: true),
        EarningsPeriod.all,
      );
      expect(board.rows[1].isYou, isTrue);
      expect(board.rows[0].isYou, isFalse);
      expect(board.rows[1].shortAddress, startsWith('0x7d29a4'));
    });

    test('profileKey may be null when the server has no alias secret', () {
      final body = weatherBoard();
      for (final row in body['entries'] as List) {
        (row as Map)['profileKey'] = null;
      }
      expect(
        RoleLeaderboard.parseWeather(body, EarningsPeriod.all).rows,
        hasLength(3),
      );
    });

    final refused = <String, void Function(Map<String, dynamic>)>{
      'not successful': (b) => b['success'] = false,
      'other metric': (b) => b['metric'] = 'streak',
      'other period': (b) => b['period'] = '7d',
      'windowed scope': (b) => b['earningsScope'] = 'period',
      'unavailable marker': (b) => b['unavailable'] = ['earnings'],
      'units not proven': (b) => (b['amountUnits'] as Map)['available'] = false,
      'other denomination': (b) =>
          (b['amountUnits'] as Map)['denomination'] = 'USD',
      'no entries list': (b) => b.remove('entries'),
      'null amount': (b) => row(b)['earningsBaseUnits'] = null,
      'float amount': (b) => row(b)['earningsBaseUnits'] = 1.5,
      'display amount disagrees': (b) => row(b)['earningsWrf'] = '1887.95',
      'rank gap': (b) => row(b)['rank'] = 2,
      'isYou missing': (b) => row(b).remove('isYou'),
      'full address on another row': (b) => row(b)['walletAddress'] =
          '0x1747000000000000000000000000000000000000',
      'address in name': (b) =>
          row(b)['displayName'] = '0x1747000000000000000000000000000000000000',
      'duplicate key': (b) =>
          row(b)['profileKey'] = (b['entries'] as List)[1]['profileKey'],
    };
    refused.forEach((name, mutate) {
      test('refuses the whole board: $name', () {
        final body = weatherBoard();
        mutate(body);
        expect(
          () => RoleLeaderboard.parseWeather(body, EarningsPeriod.all),
          throwsFormatException,
        );
      });
    });
  });

  group('Weather data tab', () {
    testWidgets('shows real rows labeled as lifetime amounts', (tester) async {
      await tester.pumpWidget(app(dioWith([], (p) => weatherBoard(period: p))));
      await openWeatherTab(tester);
      expect(find.text('1887.95124509 WRF'), findsOneWidget);
      expect(find.text('1215.47812500 WRF'), findsOneWidget);
      expect(find.text('WeatherNode-1747C0'), findsOneWidget);
      expect(find.text('0x1747…a275'), findsOneWidget);
      expect(find.textContaining('All time ranking'), findsOneWidget);
      expect(find.textContaining('Lifetime amounts'), findsOneWidget);
      expect(find.text('Earnings unavailable right now'), findsNothing);
    });

    testWidgets('a period ranks only and is never shown as a windowed amount', (
      tester,
    ) async {
      final seen = <Uri>[];
      await tester.pumpWidget(
        app(dioWith(seen, (p) => weatherBoard(period: p))),
      );
      await openWeatherTab(tester);
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(seen.last.query, 'metric=earnings&period=7d&limit=30');
      expect(find.textContaining('7 days ranking'), findsOneWidget);
      expect(find.textContaining('Lifetime amounts'), findsOneWidget);
      expect(find.textContaining('7 days payments'), findsNothing);
      expect(find.text('1887.95124509 WRF'), findsOneWidget);
    });

    testWidgets('marks the viewer\'s own row from isYou', (tester) async {
      await tester.pumpWidget(
        app(dioWith([], (p) => weatherBoard(period: p, ownRow: true))),
      );
      await openWeatherTab(tester);
      expect(find.textContaining('· You'), findsOneWidget);
    });

    testWidgets('empty board is distinct from an error', (tester) async {
      await tester.pumpWidget(
        app(dioWith([], (p) => weatherBoard(period: p)..['entries'] = [])),
      );
      await openWeatherTab(tester);
      expect(
        find.text('No station rewards have been paid yet'),
        findsOneWidget,
      );
      expect(find.text('Earnings unavailable right now'), findsNothing);
    });

    testWidgets('a 503 unavailable answer shows the error with Retry', (
      tester,
    ) async {
      var fail = true;
      final dio = Dio(BaseOptions(baseUrl: 'https://wrfcoin.test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.path != '/weather/leaderboard') {
              h.resolve(
                Response(
                  requestOptions: o,
                  data: roleBoard(o.queryParameters['role'] as String),
                ),
              );
            } else if (fail) {
              fail = false;
              h.reject(
                DioException(
                  requestOptions: o,
                  response: Response(
                    requestOptions: o,
                    statusCode: 503,
                    data: {
                      'success': false,
                      'unavailable': ['earnings'],
                      'entries': <dynamic>[],
                    },
                  ),
                ),
              );
            } else {
              h.resolve(Response(requestOptions: o, data: weatherBoard()));
            }
          },
        ),
      );
      await tester.pumpWidget(app(dio));
      await openWeatherTab(tester);
      expect(find.text('Earnings unavailable right now'), findsOneWidget);
      expect(
        find.text('We could not confirm every amount, so no ranking is shown.'),
        findsOneWidget,
      );
      expect(find.textContaining('WRF'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('1887.95124509 WRF'), findsOneWidget);
    });

    testWidgets('Forecasting stays unavailable, matching the web', (
      tester,
    ) async {
      await tester.pumpWidget(app(dioWith([], (p) => weatherBoard(period: p))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Forecasting'));
      await tester.tap(find.text('Forecasting'));
      await tester.pumpAndSettle();
      expect(find.text('Paid-event coverage unavailable'), findsOneWidget);
    });
  });

  group('screenshots', () {
    final out = Platform.environment['WRFCOIN_SCREENSHOT_DIR'];
    for (final (name, width, height) in [
      ('phone-390', 390.0, 844.0),
      ('desktop-1280', 1280.0, 800.0),
    ]) {
      for (final tab in ['Weather data', 'Nodes']) {
        testWidgets('$tab at $name', skip: out == null, (tester) async {
          await _loadRoboto();
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            app(dioWith([], (p) => weatherBoard(period: p, ownRow: true))),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text(tab));
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '$out/${tab.split(' ').first.toLowerCase()}-$name.png',
            ),
          );
        });
      }
    }
  });
}

Map<dynamic, dynamic> row(Map<String, dynamic> body) =>
    (body['entries'] as List).first as Map;

Future<void> _loadRoboto() async {
  final dir = Platform.environment['FLUTTER_ROOT'] ?? '/home/tony/flutter';
  final loader = FontLoader('Roboto');
  for (final style in ['Regular', 'Medium', 'Bold']) {
    final bytes = File(
      '$dir/bin/cache/artifacts/material_fonts/Roboto-$style.ttf',
    ).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}
