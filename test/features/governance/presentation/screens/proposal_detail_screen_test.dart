import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/advisory_proposal.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_detail_screen.dart';

import '../../fixtures/advisory_api.dart';

const _id = 'adv-a75dae543f5f9e16';

Widget _app(
  FakeAdvisoryApi api, {
  AdvisoryProposal? initial,
  UrlOpener? openUrl,
}) => ProviderScope(
  overrides: [
    governanceRepositoryProvider.overrideWithValue(
      GovernanceRepository(api.dio()),
    ),
  ],
  child: MaterialApp(
    home: openUrl == null
        ? ProposalDetailScreen(proposalId: _id, initial: initial)
        : ProposalDetailScreen(
            proposalId: _id,
            initial: initial,
            openUrl: openUrl,
          ),
  ),
);

void main() {
  testWidgets('reads the proposal by id and shows votes, deadline, deposit', (
    tester,
  ) async {
    final api = FakeAdvisoryApi([welcomeProposalJson()]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(api.calls, ['GET /api/governance/advisory/proposals/$_id']);
    expect(find.text('Welcome to Wrfcoin Governance'), findsWidgets);
    expect(find.textContaining('first example proposal'), findsOneWidget);
    expect(find.text('VOTING'), findsOneWidget);
    expect(find.text('For 1'), findsOneWidget);
    expect(find.text('Against 0'), findsOneWidget);
    expect(
      find.text('1 vote cast · needs 3 votes, 51% yes to pass'),
      findsOneWidget,
    );
    expect(find.text('14 wallets could vote'), findsOneWidget);
    expect(
      find.text('Voting ends at block 28148 (about 15 h 44 min from now)'),
      findsOneWidget,
    );
    expect(
      find.text('Estimated at about 77 s per block from block 27412.'),
      findsOneWidget,
    );
    expect(
      find.text(
        "Proposing holds 1 WRF from the proposer's wallet. It comes back "
        'when the vote is decided, and stays held if fewer than 3 wallets '
        'vote.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Proposed by 0x2796629fd0f56360264b76f938b691a408181e89'),
      findsOneWidget,
    );
  });

  testWidgets('"Vote on wrfcoin.com" opens the website and posts nothing', (
    tester,
  ) async {
    final api = FakeAdvisoryApi([welcomeProposalJson()]);
    final opened = <Uri>[];
    await tester.pumpWidget(
      _app(
        api,
        openUrl: (url, {mode = LaunchMode.platformDefault}) async {
          opened.add(url);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Vote on wrfcoin.com'), 200);
    await tester.tap(find.text('Vote on wrfcoin.com'));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('https://wrfcoin.com/governance/public')]);
    expect(api.calls.where((c) => !c.startsWith('GET ')), isEmpty);
    expect(api.calls.where((c) => c.contains('/vote')), isEmpty);
  });

  testWidgets('a decided proposal has no vote button', (tester) async {
    // Tall enough that the whole list is built, so "nothing" means absent.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeAdvisoryApi([
      {
        ...welcomeProposalJson(),
        'status': 'failed_quorum',
        'finalized_at_block': 28149,
      },
    ]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('TOO FEW VOTES'), findsOneWidget);
    expect(find.text('Decided at block 28149'), findsOneWidget);
    expect(find.text('Vote on wrfcoin.com'), findsNothing);
  });

  testWidgets('read failure with nothing to show: an error with retry', (
    tester,
  ) async {
    final api = FakeAdvisoryApi([welcomeProposalJson()], detailStatus: 503);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Vote on wrfcoin.com'), findsNothing);
  });

  testWidgets('read failure with the list copy: keeps it and says so', (
    tester,
  ) async {
    final api = FakeAdvisoryApi([welcomeProposalJson()], detailStatus: 503);
    await tester.pumpWidget(
      _app(api, initial: AdvisoryProposal.fromJson(welcomeProposalJson())),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining("Couldn't refresh this proposal"),
      findsOneWidget,
    );
    expect(find.text('For 1'), findsOneWidget);
    // Without the node's height there is no time estimate, only the block.
    expect(find.text('Voting ends at block 28148'), findsOneWidget);
  });
}
