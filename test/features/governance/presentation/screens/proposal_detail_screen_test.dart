import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
      child: MaterialApp(home: ProposalDetailScreen(proposal: proposal)),
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
    expect(find.text('Abstain'), findsNothing);
    expect(find.text('Total: 90 votes'), findsOneWidget);
  });

  testWidgets('shows vote percentages for each option', (tester) async {
    await tester.pumpWidget(buildWidget(activeProposal));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('70 (77.8%)'), findsOneWidget);
    expect(find.text('20 (22.2%)'), findsOneWidget);
  });

  testWidgets('an active proposal says voting is closed, with no vote action', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget(activeProposal));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Voting isn't open on testnet yet"), findsOneWidget);
    expect(find.text('Cast Your Vote'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.text('ACTIVE'), findsOneWidget);
  });

  testWidgets('a passed proposal shows no voting notice', (tester) async {
    await tester.pumpWidget(buildWidget(passedProposal));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Voting isn't open on testnet yet"), findsNothing);
    expect(find.text('PASSED'), findsOneWidget);
  });

  testWidgets('a rejected proposal shows no voting notice', (tester) async {
    await tester.pumpWidget(buildWidget(rejectedProposal));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Voting isn't open on testnet yet"), findsNothing);
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
    expect(find.text('Cast Your Vote'), findsNothing);
  });
}
