import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/forecast_check/data/models/forecast_check_model.dart';
import 'package:wrfcoin_mobile/features/forecast_check/data/repositories/forecast_check_repository.dart';
import 'package:wrfcoin_mobile/features/forecast_check/presentation/screens/forecast_check_screen.dart';

import '../../test_helpers/stub_http_adapter.dart';
import 'forecast_check_fixtures.dart';

Future<StubHttpAdapter> _pump(
  WidgetTester tester,
  (int, Object?)? Function(RequestOptions) answer,
) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final adapter = StubHttpAdapter(answer);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        forecastCheckRepositoryProvider.overrideWithValue(
          ForecastCheckRepository(stubDio(adapter)),
        ),
      ],
      child: const MaterialApp(home: ForecastCheckScreen()),
    ),
  );
  return adapter;
}

void main() {
  testWidgets('shows a loading state before the answer', (tester) async {
    await _pump(tester, (_) => (200, emptySummary));
    expect(find.text('Loading scores…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Loading scores…'), findsNothing);
  });

  testWidgets('loaded: every figure is the server\'s', (tester) async {
    final adapter = await _pump(tester, (_) => (200, loadedSummary));
    await tester.pumpAndSettle();

    expect(adapter.requests.single.path, '/forecast-verification/summary');
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('Scored (30 days)'), findsOneWidget);
    expect(
      find.text('1,234 scored · average miss 0.81 °C · bias -0.25 °C'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Same forecasts: on chain 0.75 °C, NOAA 1.50 °C, over 900 forecasts',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('NOAA hourly forecasts do not include pressure.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Temperature: forecast 21.50 °C, measured 21.00 °C, off by +0.50 °C',
      ),
      findsOneWidget,
    );
    expect(
      find.text('NOAA: 23.00 °C, off by +2.00 °C, 6 h ahead'),
      findsOneWidget,
    );
    expect(find.text('Waiting for readings'), findsWidgets);
    expect(find.text('Pressure: forecast 1012.50 hPa'), findsOneWidget);
    expect(
      find.text('No station reading landed on chain for the target hour.'),
      findsOneWidget,
    );
    expect(find.textContaining('model not stated'), findsOneWidget);
    expect(find.text('Hand in your forecast'), findsOneWidget);
  });

  testWidgets('empty: the live answer shows reasons and no invented numbers', (
    tester,
  ) async {
    await _pump(tester, (_) => (200, emptySummary));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No forecast has been scored against station readings in this window yet.',
      ),
      findsOneWidget,
    );
    expect(find.text('No forecast has been handed in yet.'), findsOneWidget);
    expect(find.text('0 scored · average miss Unavailable'), findsNWidgets(3));
    expect(find.textContaining('Against NOAA: Unavailable'), findsNWidgets(3));
    expect(find.textContaining('°C'), findsNothing);
  });

  testWidgets('a value the server left out stays unknown, not zero', (
    tester,
  ) async {
    await _pump(
      tester,
      (_) => (
        200,
        {
          'status': 'unavailable',
          'variables': <Object>[],
          'recent': <Object>[],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text('Nothing has been scored yet.'), findsOneWidget);
    expect(find.text('Scored'), findsOneWidget);
  });

  group('error', () {
    testWidgets('server failure says unavailable and retries', (tester) async {
      var up = false;
      final adapter = await _pump(
        tester,
        (_) => up ? (200, emptySummary) : (500, {'error': 'x'}),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Forecast check is unavailable right now.'),
        findsOneWidget,
      );
      expect(find.text('Hand in your forecast'), findsNothing);

      up = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(adapter.requests.length, 2);
      expect(find.text('No forecast has been handed in yet.'), findsOneWidget);
    });

    testWidgets('offline says unavailable', (tester) async {
      await _pump(tester, (_) => null);
      await tester.pumpAndSettle();
      expect(
        find.text('Forecast check is unavailable right now.'),
        findsOneWidget,
      );
    });

    testWidgets('an HTML fallback page is not data', (tester) async {
      await _pump(tester, (_) => (200, '<!doctype html><html></html>'));
      await tester.pumpAndSettle();
      expect(
        find.text('Forecast check is unavailable right now.'),
        findsOneWidget,
      );
    });

    testWidgets('404 says not switched on, with no form', (tester) async {
      await _pump(tester, (_) => (404, {'error': 'Not found'}));
      await tester.pumpAndSettle();
      expect(
        find.text('Forecast check is not switched on yet'),
        findsOneWidget,
      );
      expect(find.text('Hand in your forecast'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('429 says wait and try again', (tester) async {
      await _pump(tester, (_) => (429, {'error': 'slow'}));
      await tester.pumpAndSettle();
      expect(find.textContaining('Too many requests'), findsOneWidget);
    });
  });

  group('hand in', () {
    final commit =
        '{"commit_id":"${'A' * 64}","nonce":"n1","timestamp":1800000000}';

    Future<StubHttpAdapter> pumpForm(
      WidgetTester tester,
      (int, Object?) post,
    ) async {
      final adapter = await _pump(
        tester,
        (o) => o.method == 'POST' ? post : (200, emptySummary),
      );
      await tester.pumpAndSettle();
      return adapter;
    }

    Future<void> submit(WidgetTester tester, String c, String d) async {
      await tester.enterText(find.byType(TextField).at(0), c);
      await tester.enterText(find.byType(TextField).at(1), d);
      await tester.tap(find.text('Hand in forecast'));
      await tester.pumpAndSettle();
    }

    testWidgets('sends the record and reloads the summary', (tester) async {
      final adapter = await pumpForm(tester, (201, {'commitId': 'a' * 64}));
      await submit(tester, commit, ' {"horizon_hours":6}\r\n');

      final post = adapter.requests.firstWhere((r) => r.method == 'POST');
      expect(post.path, '/forecast-verification/forecasts');
      expect(post.data, {
        'commitId': 'a' * 64,
        'nonce': 'n1',
        'timestamp': 1800000000,
        'data': '{"horizon_hours":6}',
      });
      expect(post.extra['noRetry'], isTrue);
      expect(find.textContaining('Added.'), findsOneWidget);
      expect(adapter.requests.where((r) => r.method == 'GET').length, 2);
    });

    testWidgets('names a refusal in plain words', (tester) async {
      await pumpForm(tester, (
        409,
        {
          'success': false,
          'error': {'code': 'NOT_REVEALED', 'message': 'x'},
        },
      ));
      await submit(tester, commit, '{}');
      expect(
        find.text('Reveal this forecast on chain first, then hand it in.'),
        findsOneWidget,
      );
    });

    testWidgets('bad files are refused here without a request', (tester) async {
      final adapter = await pumpForm(tester, (201, <String, Object>{}));
      await submit(tester, 'not json', '{}');
      expect(find.text('commit.json is not valid JSON.'), findsOneWidget);
      expect(adapter.requests.any((r) => r.method == 'POST'), isFalse);
    });
  });

  group('ForecastHandIn.fromFiles', () {
    test('needs a 64-character id, nonce, timestamp and data', () {
      expect(
        ForecastHandIn.fromFiles('{"commit_id":"abc"}', '{}').$2,
        'commit.json has no 64-character commit_id.',
      );
      expect(
        ForecastHandIn.fromFiles('{"commit_id":"${'a' * 64}"}', '{}').$2,
        'commit.json needs its nonce and timestamp.',
      );
      expect(
        ForecastHandIn.fromFiles(
          '{"commit_id":"${'a' * 64}","nonce":"n","timestamp":1}',
          '  ',
        ).$2,
        'Paste the contents of data.json.',
      );
      expect(ForecastHandIn.fromFiles('[1]', '{}').$2, isNotNull);
    });
  });
}
