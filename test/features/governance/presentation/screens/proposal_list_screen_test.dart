import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_list_screen.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/widgets/settings_gear_button.dart';

import '../../fixtures/advisory_api.dart';

Widget _app(FakeAdvisoryApi api, {GoRouter? router}) {
  final overrides = [
    governanceRepositoryProvider.overrideWithValue(
      GovernanceRepository(api.dio()),
    ),
  ];
  return ProviderScope(
    overrides: overrides,
    child: router == null
        ? const MaterialApp(home: ProposalListScreen())
        : MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows the live advisory proposal from the advisory route', (
    tester,
  ) async {
    final api = FakeAdvisoryApi([welcomeProposalJson()]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(api.calls, [
      'GET /api/governance/advisory/proposals?limit=20&offset=0',
    ]);
    expect(find.text('Welcome to Wrfcoin Governance'), findsOneWidget);
    expect(find.text('VOTING'), findsOneWidget);
    expect(find.text('For 1'), findsOneWidget);
    expect(find.text('Against 0'), findsOneWidget);
    expect(
      find.text('1 vote cast · needs 3 votes, 51% yes to pass'),
      findsOneWidget,
    );
    expect(
      find.text('Voting ends at block 28148 (about 15 h 44 min from now)'),
      findsOneWidget,
    );
    expect(find.text('1 total'), findsOneWidget);
    expect(find.byType(SettingsGearButton), findsOneWidget);
  });

  testWidgets('tapping a proposal opens its detail by id', (tester) async {
    final api = FakeAdvisoryApi([welcomeProposalJson()]);
    String? pushed;
    // The list pushes the absolute /govern/proposal path.
    final shim = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ProposalListScreen()),
        GoRoute(
          path: '/govern/proposal',
          builder: (_, state) {
            pushed = (state.extra as dynamic).id as String;
            return const Scaffold(body: Text('detail'));
          },
        ),
      ],
    );
    await tester.pumpWidget(_app(api, router: shim));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome to Wrfcoin Governance'));
    await tester.pumpAndSettle();
    expect(pushed, 'adv-a75dae543f5f9e16');
  });

  testWidgets('empty list while active says how proposals are made', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FakeAdvisoryApi(const [])));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No advisory proposals yet. Proposals are made with the WRFCoin CLI '
        'or on wrfcoin.com for now.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Treasury'), findsNothing);
  });

  testWidgets('feature not active: an honest empty state', (tester) async {
    await tester.pumpWidget(
      _app(FakeAdvisoryApi(const [], featureActive: false)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Governance isn't active on this network yet, so there are no "
        'proposals to show.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('total'), findsNothing);
  });

  testWidgets('route failure: an error with retry, which reads again', (
    tester,
  ) async {
    final api = FakeAdvisoryApi(const [], listStatus: 503);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Wrfcoin Governance'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(2));
  });

  testWidgets('a failed later page keeps the list and says so', (tester) async {
    final api = FakeAdvisoryApi([
      for (var n = 1; n <= 25; n++) syntheticProposalJson(n),
    ], failAtOffset: 20);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(
      find.text("Some proposals couldn't be loaded. Pull down to try again."),
      findsOneWidget,
    );
    expect(find.text('Synthetic proposal 1'), findsOneWidget);
  });

  testWidgets('never reads the older /governance/proposals list', (
    tester,
  ) async {
    final api = FakeAdvisoryApi([welcomeProposalJson()]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(
      api.calls.where((c) => c.contains('/api/governance/proposals')),
      isEmpty,
    );
  });
}
