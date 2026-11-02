import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/competitions/data/models/competition_model.dart';
import 'package:wrfcoin_mobile/features/competitions/data/repositories/competition_repository.dart';
import 'package:wrfcoin_mobile/features/competitions/presentation/screens/competitions_screen.dart';

import '../../test_helpers/stub_http_adapter.dart';
import 'competition_fixtures.dart';

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
        competitionRepositoryProvider.overrideWithValue(
          CompetitionRepository(stubDio(adapter)),
        ),
      ],
      child: const MaterialApp(home: CompetitionsScreen()),
    ),
  );
  return adapter;
}

(int, Object?)? Function(RequestOptions) _routes({
  required Map<String, dynamic> list,
  required Map<String, dynamic> current,
  Map<String, dynamic>? week44,
}) =>
    (options) => switch (options.path) {
      '/competitions' => (200, list),
      '/competitions/current' => (200, current),
      '/competitions/2026-W44' when week44 != null => (200, week44),
      _ => (404, {'error': 'none'}),
    };

void main() {
  testWidgets('shows a loading state before the answer', (tester) async {
    await _pump(tester, _routes(list: emptyWeeks, current: emptyCurrent));
    expect(find.text('Loading standings…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Loading standings…'), findsNothing);
  });

  testWidgets('loaded: standings, rule text and past weeks', (tester) async {
    await _pump(tester, _routes(list: loadedWeeks, current: loadedCurrent));
    await tester.pumpAndSettle();

    expect(find.text('This week · standings'), findsOneWidget);
    expect(find.text('4 shown'), findsOneWidget);
    expect(find.text('Week 45'), findsOneWidget);
    expect(find.text('Nov 2 – Nov 8'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('0xab10…121'), findsOneWidget);
    expect(find.text('1,000 pts'), findsOneWidget);
    expect(find.textContaining('Live as of block 11,598'), findsOneWidget);
    expect(
      find.text('Points only. No WRF is paid and nothing is staked.'),
      findsOneWidget,
    );
    expect(find.text('Past weeks'), findsOneWidget);
    expect(find.text('Week 44 · Oct 26 – Nov 1'), findsOneWidget);
    expect(find.textContaining('Winner 0xab10…121'), findsOneWidget);
    expect(find.text('You'), findsNothing);
  });

  testWidgets('your own row is shown when it is outside the top', (
    tester,
  ) async {
    await _pump(
      tester,
      _routes(list: loadedWeeks, current: loadedWithYouBelow),
    );
    await tester.pumpAndSettle();
    expect(find.text('You'), findsOneWidget);
    expect(find.text('#77'), findsOneWidget);
    expect(find.text('0x${'ab' * 20}'), findsOneWidget);
  });

  testWidgets('choosing a past week reads that week', (tester) async {
    final adapter = await _pump(
      tester,
      _routes(list: loadedWeeks, current: loadedCurrent, week44: finalWeek44),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Week 44'));
    await tester.pumpAndSettle();

    expect(
      adapter.requests.map((r) => r.path),
      contains('/competitions/2026-W44'),
    );
    expect(find.text('Week 44 · standings'), findsOneWidget);
    expect(find.text('Final'), findsWidgets);
    expect(
      find.textContaining('Final, read through block 11,500'),
      findsOneWidget,
    );
  });

  testWidgets('empty: the live answer invents nobody', (tester) async {
    await _pump(tester, _routes(list: emptyWeeks, current: emptyCurrent));
    await tester.pumpAndSettle();

    expect(find.text('No points yet this week'), findsOneWidget);
    expect(find.text('0 shown'), findsOneWidget);
    expect(find.textContaining(' pts'), findsNothing);
    expect(find.text('No scored forecasts'), findsOneWidget);
  });

  group('error', () {
    testWidgets('503 names the missing index and retries', (tester) async {
      var up = false;
      final adapter = await _pump(
        tester,
        (o) => up
            ? _routes(list: emptyWeeks, current: emptyCurrent)(o)
            : (503, {'status': 'unavailable'}),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Forecast competitions are not available on this network yet',
        ),
        findsOneWidget,
      );
      expect(find.text('Past weeks'), findsNothing);

      up = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(adapter.requests.length, greaterThan(2));
      expect(find.text('No points yet this week'), findsOneWidget);
    });

    testWidgets('offline says unavailable', (tester) async {
      await _pump(tester, (_) => null);
      await tester.pumpAndSettle();
      expect(
        find.text('Forecast competitions unavailable right now.'),
        findsOneWidget,
      );
    });

    testWidgets('an HTML fallback page is not data', (tester) async {
      await _pump(tester, (_) => (200, '<!doctype html>'));
      await tester.pumpAndSettle();
      expect(
        find.text('Forecast competitions unavailable right now.'),
        findsOneWidget,
      );
    });

    testWidgets('a 200 with no competition is not data', (tester) async {
      await _pump(tester, (_) => (200, {'success': true}));
      await tester.pumpAndSettle();
      expect(
        find.text('Forecast competitions unavailable right now.'),
        findsOneWidget,
      );
    });

    testWidgets('404 says no competition for that week', (tester) async {
      await _pump(tester, (_) => (404, {'error': {}}));
      await tester.pumpAndSettle();
      expect(
        find.text('No competition for that week on this chain.'),
        findsOneWidget,
      );
    });

    testWidgets('429 says wait and try again', (tester) async {
      await _pump(tester, (_) => (429, {'error': 'slow'}));
      await tester.pumpAndSettle();
      expect(find.textContaining('Too many requests'), findsOneWidget);
    });
  });

  group('formatting', () {
    final now = DateTime.utc(2026, 11, 2);

    test('competitionTimeLeft counts down and stops at the end', () {
      String? left(Duration d) =>
          competitionTimeLeft(now.add(d).toIso8601String(), now: now);
      expect(left(const Duration(days: 2, hours: 4)), '2 days 4 h');
      expect(left(const Duration(days: 1)), '1 day 0 h');
      expect(left(const Duration(hours: 3, minutes: 5)), '3 h 5 min');
      expect(left(const Duration(minutes: 9)), '9 min');
      expect(left(const Duration(seconds: 10)), '1 min');
      expect(left(const Duration(seconds: -1)), isNull);
      expect(competitionTimeLeft('nonsense', now: now), isNull);
      expect(competitionTimeLeft(null, now: now), isNull);
    });

    test('competitionWeekNumber', () {
      expect(competitionWeekNumber('2026-W05'), 'Week 5');
      expect(competitionWeekNumber('oops'), 'oops');
    });
  });
}
