import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/vote_screen.dart';

void main() {
  const proposal = ProposalModel(
    id: 'p1',
    title: 'Keep the testnet faucet open',
    description: 'Synthetic proposal.',
    status: 'active',
  );

  testWidgets('explains why voting is closed and offers no way to vote', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: VoteScreen(proposal: proposal)),
    );

    expect(find.text('Keep the testnet faucet open'), findsOneWidget);
    expect(find.text("Voting isn't open on testnet yet"), findsOneWidget);
    expect(find.textContaining('locked stake'), findsOneWidget);

    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Vote For'), findsNothing);
    expect(find.text('Vote Against'), findsNothing);
    expect(find.text('Submit Vote'), findsNothing);
    expect(find.textContaining('Vote cast'), findsNothing);
  });
}
