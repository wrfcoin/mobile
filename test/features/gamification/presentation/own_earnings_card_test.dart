import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/role_earnings_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/role_earnings_repository.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/providers/role_earnings_provider.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/widgets/role_earnings_board.dart';

import '../../../fixtures/role_earnings_fixture.dart';
import '../../../fixtures/weather_earnings_fixture.dart';

const _viewer = '0x7d29a40000000000000000000000000000000cb2';
const _weatherKey = 'c_9649ba143a37dd220c1df06a';

class _Edge {
  _Edge({
    this.weatherOwn = false,
    this.producerOwn = false,
    this.weatherFails = false,
    this.profileFails = false,
    this.boardsFail = false,
  });
  final bool weatherOwn, producerOwn, weatherFails, profileFails, boardsFail;
  final seen = <Uri>[];

  Dio dio() {
    final dio = Dio(BaseOptions(baseUrl: 'https://wrfcoin.test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          seen.add(o.uri);
          void fail() => h.reject(
            DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: o, statusCode: 503),
            ),
          );
          if (o.path == '/weather/leaderboard') {
            return weatherFails
                ? fail()
                : h.resolve(
                    Response(
                      requestOptions: o,
                      data: weatherBoard(ownRow: weatherOwn),
                    ),
                  );
          }
          if (o.path == '/earnings/leaderboard') {
            if (boardsFail) return fail();
            final body = roleBoard(o.queryParameters['role'] as String);
            for (final row in body['rows'] as List) {
              (row as Map)['isYou'] = producerOwn;
            }
            return h.resolve(Response(requestOptions: o, data: body));
          }
          if (profileFails) return fail();
          h.resolve(
            Response(requestOptions: o, data: roleFixture()['ownProfile']),
          );
        },
      ),
    );
    return dio;
  }
}

Widget _app(_Edge edge) => ProviderScope(
  overrides: [
    earningsReadProvider.overrideWith((ref) async => true),
    ownEarningsAddressProvider.overrideWith((ref) async => _viewer),
    roleEarningsRepositoryProvider.overrideWithValue(
      RoleEarningsRepository(edge.dio()),
    ),
  ],
  child: const MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: OwnRoleEarningsSummary()),
    ),
  ),
);

void main() {
  void expectAdmitted(_Edge edge) {
    for (final uri in edge.seen) {
      expect(uri.path, isNot(contains('0x')), reason: 'no raw address');
      if (uri.path.contains('/operators/')) {
        expect(
          uri.path,
          matches(RegExp(r'/operators/c_[0-9a-f]{24}/profile$')),
        );
        expect(uri.query, isEmpty);
      }
    }
  }

  testWidgets('on the weather board: real weather earnings and role totals', (
    tester,
  ) async {
    final edge = _Edge(weatherOwn: true);
    await tester.pumpWidget(_app(edge));
    await tester.pumpAndSettle();
    expect(
      find.text('1215.47812500 WRF (lifetime station rewards)'),
      findsOneWidget,
    );
    expect(find.text('90071992.54741000 WRF'), findsNWidgets(2));
    expect(find.text(kNodePaymentsNotice), findsOneWidget);
    expect(
      edge.seen.map((u) => u.path),
      contains('/api/operators/$_weatherKey/profile'),
    );
    expect(find.text('Your role earnings are unavailable'), findsNothing);
    expectAdmitted(edge);
  });

  testWidgets('weather row still shows when the profile cannot be read', (
    tester,
  ) async {
    final edge = _Edge(weatherOwn: true, profileFails: true);
    await tester.pumpWidget(_app(edge));
    await tester.pumpAndSettle();
    expect(
      find.text('1215.47812500 WRF (lifetime station rewards)'),
      findsOneWidget,
    );
    expect(find.text('90071992.54741000 WRF'), findsNothing);
    expect(find.textContaining('Through height'), findsNothing);
    expect(find.text('Your role earnings are unavailable'), findsNothing);
  });

  testWidgets('key from a producer row: says not on the weather board', (
    tester,
  ) async {
    final edge = _Edge(producerOwn: true);
    await tester.pumpWidget(_app(edge));
    await tester.pumpAndSettle();
    expect(find.text('Not among the top 30 weather earners'), findsOneWidget);
    expect(find.text('90071992.54741000 WRF'), findsNWidgets(2));
    expectAdmitted(edge);
  });

  testWidgets('on no board: the card is hidden, with no error', (tester) async {
    final edge = _Edge();
    await tester.pumpWidget(_app(edge));
    await tester.pumpAndSettle();
    expect(find.text('Your role payments · All time'), findsNothing);
    expect(find.text('Your role earnings are unavailable'), findsNothing);
    expect(edge.seen.where((u) => u.path.contains('/operators/')), isEmpty);
    expectAdmitted(edge);
  });

  testWidgets('reads that fail stay an error with Retry, not "no earnings"', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Edge(weatherFails: true, boardsFail: true)));
    await tester.pumpAndSettle();
    expect(find.text('Your role earnings are unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  group('screenshots', () {
    final out = Platform.environment['WRFCOIN_SCREENSHOT_DIR'];
    for (final (name, width, height) in [
      ('phone-390', 390.0, 844.0),
      ('desktop-1280', 1280.0, 800.0),
    ]) {
      testWidgets('own earnings at $name', skip: out == null, (tester) async {
        final root =
            Platform.environment['FLUTTER_ROOT'] ?? '/home/tony/flutter';
        final loader = FontLoader('Roboto');
        for (final style in ['Regular', 'Medium', 'Bold']) {
          final bytes = File(
            '$root/bin/cache/artifacts/material_fonts/Roboto-$style.ttf',
          ).readAsBytesSync();
          loader.addFont(Future.value(ByteData.view(bytes.buffer)));
        }
        await loader.load();
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(_Edge(weatherOwn: true)));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('$out/own-earnings-$name.png'),
        );
      });
    }
  });
}
