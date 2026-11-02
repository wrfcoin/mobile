import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/duels/data/models/duel_model.dart';
import 'package:wrfcoin_mobile/features/duels/data/repositories/duel_repository.dart';
import 'package:wrfcoin_mobile/features/duels/presentation/providers/duels_provider.dart';
import 'package:wrfcoin_mobile/features/duels/presentation/screens/forecast_duel_screen.dart';
import 'package:wrfcoin_mobile/features/duels/presentation/screens/forecast_duels_screen.dart';

import 'duel_fixtures.dart';

class FakeDuels implements DuelRepository {
  FakeDuels({this.board, this.duel, this.failure, this.refusal});

  DuelBoard? board;
  Duel? duel;
  Failure? failure;
  Failure? refusal;
  final List<String> calls = [];
  OpenDuelInput? opened;

  Either<Failure, Duel> _write(String name) {
    calls.add(name);
    return refusal != null ? Left(refusal!) : Right(duel!);
  }

  @override
  Future<Either<Failure, DuelBoard>> getBoard() async =>
      failure != null ? Left(failure!) : Right(board!);

  @override
  Future<Either<Failure, Duel>> getDuel(String id) async =>
      failure != null ? Left(failure!) : Right(duel!);

  @override
  Future<Either<Failure, Duel>> open(OpenDuelInput input) async {
    opened = input;
    return _write('open');
  }

  @override
  Future<Either<Failure, Duel>> accept(String id) async => _write('accept');

  @override
  Future<Either<Failure, Duel>> linkForecast(
    String id,
    String commitId,
  ) async => _write('link:$commitId');

  @override
  Future<Either<Failure, Duel>> handInRecord(
    String id,
    DuelRecordInput record,
  ) async => _write('record:${record.commitId}');
}

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  DuelRepository repository, {
  String? wallet = duelWalletB,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/collect/duels/:id',
        builder: (_, state) => Text(
          'pushed ${state.pathParameters['id']}',
          textDirection: TextDirection.ltr,
        ),
      ),
      GoRoute(path: '/wallet', builder: (_, _) => const Text('wallet page')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        duelRepositoryProvider.overrideWithValue(repository),
        duelWalletProvider.overrideWith((ref) async => wallet),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final fullBoard = DuelBoard.fromJson({
    'open': [openDuelJson()],
    'live': [liveDuelJson()],
    'finished': [finishedDuelJson()],
  });

  group('board', () {
    testWidgets('loaded: shows every section from the server', (tester) async {
      await _pump(
        tester,
        const ForecastDuelsScreen(),
        FakeDuels(board: fullBoard),
      );
      expect(find.text('Open: take the other side (1)'), findsOneWidget);
      expect(find.text('In progress (1)'), findsOneWidget);
      expect(find.text('Finished (1)'), findsOneWidget);
      expect(find.text('Waiting for an opponent'), findsOneWidget);
      expect(find.text('Open seat'), findsOneWidget);
      expect(find.text('12.5 °C'), findsOneWidget);
      expect(find.text('0.25000000 WRF'), findsOneWidget);
      expect(find.text('Challenger · Winner'), findsOneWidget);
      expect(find.textContaining('Hidden until revealed'), findsWidgets);
      expect(find.text(duelFreePlayNote), findsOneWidget);
    });

    testWidgets('loading: says so, invents nothing', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duelBoardProvider.overrideWith(
              (ref) => Future.delayed(const Duration(days: 1), () => throw 'x'),
            ),
            duelWalletProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: ForecastDuelsScreen()),
        ),
      );
      await tester.pump();
      expect(find.text('Loading duels…'), findsOneWidget);
      expect(find.textContaining('(0)'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(days: 2));
    });

    testWidgets('empty: honest empty lines', (tester) async {
      await _pump(
        tester,
        const ForecastDuelsScreen(),
        FakeDuels(board: const DuelBoard()),
      );
      expect(
        find.text('No open duels right now. Open one above.'),
        findsOneWidget,
      );
      expect(find.text('No duel is running.'), findsOneWidget);
      expect(find.text('No duel has finished yet.'), findsOneWidget);
    });

    testWidgets('error: not an empty board, and retry works', (tester) async {
      final repository = FakeDuels(
        failure: const ServerFailure('down', statusCode: 503),
      );
      await _pump(tester, const ForecastDuelsScreen(), repository);
      expect(find.textContaining('No open duels'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      repository
        ..failure = null
        ..board = fullBoard;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('In progress (1)'), findsOneWidget);
    });

    testWidgets('feature off: says it is not switched on', (tester) async {
      await _pump(
        tester,
        const ForecastDuelsScreen(),
        FakeDuels(failure: const NotAvailableFailure('off', statusCode: 404)),
      );
      expect(
        find.text('Forecast duels are not switched on yet'),
        findsOneWidget,
      );
    });

    testWidgets('no wallet: points at the wallet, offers no form', (
      tester,
    ) async {
      await _pump(
        tester,
        const ForecastDuelsScreen(),
        FakeDuels(board: const DuelBoard()),
        wallet: null,
      );
      expect(find.text('Open duel'), findsNothing);
      await tester.tap(find.text('Open your wallet'));
      await tester.pumpAndSettle();
      expect(find.text('wallet page'), findsOneWidget);
    });

    testWidgets('open: a bad alias cannot be sent, a good one goes to the '
        'new duel', (tester) async {
      final repository = FakeDuels(
        board: const DuelBoard(),
        duel: Duel.fromJson(openDuelJson()),
      );
      await _pump(tester, const ForecastDuelsScreen(), repository);
      final button = find.widgetWithText(FilledButton, 'Open duel');
      await tester.enterText(find.byType(TextField).first, 'not-an-alias');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.tap(find.text("Use this phone's station"));
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repository.calls, ['open']);
      expect(
        stationAliasPattern.hasMatch(repository.opened!.stationAlias),
        isTrue,
      );
      expect(find.text('pushed $duelIdForTest'), findsOneWidget);
    });

    testWidgets('open: a refusal is shown in the form', (tester) async {
      final repository = FakeDuels(
        board: const DuelBoard(),
        refusal: const ValidationFailure(
          'You already have 5 unresolved duels.',
        ),
      );
      await _pump(tester, const ForecastDuelsScreen(), repository);
      await tester.enterText(find.byType(TextField).first, 'st_7d29a4c1e0b8');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Open duel'));
      await tester.pumpAndSettle();
      expect(find.text('You already have 5 unresolved duels.'), findsOneWidget);
    });
  });

  group('one duel', () {
    Duel duel(Map<String, dynamic> json) => Duel.fromJson(json);

    testWidgets('another wallet can accept', (tester) async {
      final repository = FakeDuels(duel: duel(openDuelJson()));
      await _pump(
        tester,
        const ForecastDuelScreen(id: duelIdForTest),
        repository,
      );
      await tester.tap(find.text('Accept this duel'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['accept']);
      expect(
        find.text('You are in. Link your forecast before the lock.'),
        findsOneWidget,
      );
    });

    testWidgets('the creator is not offered accept', (tester) async {
      await _pump(
        tester,
        const ForecastDuelScreen(id: duelIdForTest),
        FakeDuels(duel: duel(openDuelJson())),
        wallet: duelWalletA,
      );
      expect(find.text('Accept this duel'), findsNothing);
    });

    testWidgets('a duel for another wallet is not offered accept', (
      tester,
    ) async {
      await _pump(
        tester,
        const ForecastDuelScreen(id: duelIdForTest),
        FakeDuels(duel: duel(openDuelJson(invited: duelWalletA))),
      );
      expect(find.text('Accept this duel'), findsNothing);
      expect(find.textContaining('Invited:'), findsOneWidget);
    });

    testWidgets('a player links a valid commit id only', (tester) async {
      final repository = FakeDuels(duel: duel(committingDuelJson()));
      await _pump(
        tester,
        const ForecastDuelScreen(id: duelIdForTest),
        repository,
      );
      final button = find.widgetWithText(FilledButton, 'Link forecast');
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'AB' * 32);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repository.calls, ['link:${'ab' * 32}']);
    });

    testWidgets('a bad commit.json is caught before anything is sent', (
      tester,
    ) async {
      final repository = FakeDuels(duel: duel(liveDuelJson()));
      await _pump(
        tester,
        const ForecastDuelScreen(id: duelIdForTest),
        repository,
      );
      await tester.enterText(find.byType(TextField).first, 'not json');
      await tester.enterText(find.byType(TextField).last, '{}');
      await tester.pump();
      await tester.tap(find.text('Hand in record'));
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      expect(find.text('commit.json is not valid JSON.'), findsOneWidget);
    });

    testWidgets('a good record is handed in', (tester) async {
      final repository = FakeDuels(duel: duel(liveDuelJson()));
      await _pump(
        tester,
        const ForecastDuelScreen(id: duelIdForTest),
        repository,
      );
      await tester.enterText(
        find.byType(TextField).first,
        '{"commit_id":"CD","nonce":"n","timestamp":"t"}',
      );
      await tester.enterText(find.byType(TextField).last, '{"a":1}');
      await tester.pump();
      await tester.tap(find.text('Hand in record'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['record:cd']);
      expect(find.text('Record checked against the chain.'), findsOneWidget);
    });

    testWidgets('a decided duel shows the verdict and no actions', (
      tester,
    ) async {
      await _pump(
        tester,
        const ForecastDuelScreen(id: duelIdForTest),
        FakeDuels(duel: duel(finishedDuelJson())),
        wallet: duelWalletA,
      );
      expect(find.textContaining('its oracle receipt scored'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Accept this duel'), findsNothing);
    });

    testWidgets('a malformed id asks nothing of the server', (tester) async {
      await _pump(tester, const ForecastDuelScreen(id: 'nope'), FakeDuels());
      expect(find.text('No duel here'), findsOneWidget);
    });

    testWidgets('an unknown id says no duel; an outage says try again', (
      tester,
    ) async {
      await _pump(
        tester,
        const ForecastDuelScreen(id: duelIdForTest),
        FakeDuels(failure: const NotAvailableFailure('none', statusCode: 404)),
      );
      expect(find.text('No duel here'), findsOneWidget);
    });

    testWidgets('an outage offers a retry', (tester) async {
      await _pump(
        tester,
        const ForecastDuelScreen(id: duelIdForTest),
        FakeDuels(failure: const ServerFailure('down', statusCode: 503)),
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
