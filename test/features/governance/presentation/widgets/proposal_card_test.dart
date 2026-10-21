import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/widgets/proposal_card.dart';

void main() {
  const proposal = ProposalModel(
    id: 'prop-1',
    title: 'Upgrade Consensus',
    description: 'Reduce block time',
    proposalType: 'economic',
    status: 'active',
    votesFor: 8,
    votesAgainst: 2,
    votesAbstain: 0,
  );

  testWidgets('renders title, type, and status chips', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProposalCard(proposal: proposal)),
      ),
    );

    expect(find.text('Upgrade Consensus'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('economic'), findsOneWidget);
  });

  testWidgets('renders vote totals', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProposalCard(proposal: proposal)),
      ),
    );

    expect(find.text('For: 8'), findsOneWidget);
    expect(find.text('Against: 2'), findsOneWidget);
  });
}
