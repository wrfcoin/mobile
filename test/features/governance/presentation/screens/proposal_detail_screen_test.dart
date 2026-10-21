import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_detail_screen.dart';

import '../../../../test_helpers/fakes.dart';

void main() {
  const activeProposal = ProposalModel(
    id: 'p1',
    title: 'Upgrade Block Time',
    description: 'Reduce target block time from 10s to 6s.',
    proposalType: 'platform_upgrade',
    status: 'active',
    votesFor: 70,
    votesAgainst: 20,
    votesAbstain: 10,
  );

  const passedProposal = ProposalModel(
    id: 'p2',
    title: 'Treasury Grant Q1',
    description: 'Allocate 50k WRF for development.',
    proposalType: 'treasury_spending',
    status: 'passed',
    votesFor: 80,
    votesAgainst: 10,
    votesAbstain: 5,
  );

  const rejectedProposal = ProposalModel(
    id: 'p3',
    title: 'Deprecate Legacy Module',
    description: 'Remove the old PoW consensus module.',
    proposalType: 'module_deprecation',
    status: 'rejected',
    votesFor: 10,
    votesAgainst: 90,
    votesAbstain: 0,
  );

  Widget buildWidget(ProposalModel proposal) {
    return ProviderScope(
      overrides: [
        appPreferencesStoreProvider.overrideWithValue(
          TestAppPreferencesStore(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/govern',
          routes: [
            GoRoute(
              path: '/govern',
              builder: (context, state) =>
                  ProposalDetailScreen(proposal: proposal),
              routes: [
                GoRoute(
                  path: 'vote',
                  builder: (context, state) =>
                      const Scaffold(body: Text('Vote Page')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('renders title, description, and vote bars', (tester) async {
    await tester.pumpWidget(buildWidget(activeProposal));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Upgrade Block Time'), findsWidgets);
    expect(
      find.text('Reduce target block time from 10s to 6s.'),
      findsOneWidget,
    );
    expect(find.text('For'), findsOneWidget);
    expect(find.text('Against'), findsOneWidget);
    expect(find.text('Abstain'), findsOneWidget);
    expect(find.text('Total: 100 votes'), findsOneWidget);
  });

  testWidgets('shows vote percentages for each option', (tester) async {
    await tester.pumpWidget(buildWidget(activeProposal));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('70 (70.0%)'), findsOneWidget);
    expect(find.text('20 (20.0%)'), findsOneWidget);
    expect(find.text('10 (10.0%)'), findsOneWidget);
  });

  testWidgets('shows Cast Your Vote button for active proposals', (tester) async {
    await tester.pumpWidget(buildWidget(activeProposal));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Cast Your Vote'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
  });

  testWidgets('hides vote button for passed proposals', (tester) async {
    await tester.pumpWidget(buildWidget(passedProposal));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Cast Your Vote'), findsNothing);
    expect(find.text('PASSED'), findsOneWidget);
  });

  testWidgets('hides vote button for rejected proposals', (tester) async {
    await tester.pumpWidget(buildWidget(rejectedProposal));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Cast Your Vote'), findsNothing);
    expect(find.text('REJECTED'), findsOneWidget);
  });

  testWidgets('shows zero-vote edge case with 0% bars', (tester) async {
    const zeroVotes = ProposalModel(
      id: 'p0',
      title: 'New Proposal',
      description: 'No votes yet.',
      status: 'active',
    );

    await tester.pumpWidget(buildWidget(zeroVotes));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Total: 0 votes'), findsOneWidget);
    expect(find.text('Cast Your Vote'), findsOneWidget);
  });
}
