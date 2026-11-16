import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/preferences/app_preferences.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/advisory_proposal.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_detail_screen.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_list_screen.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/vote_screen.dart';

import '../../test_helpers/fakes.dart';

// Renders with SCREENSHOT_FONTS set to Flutter's bin/cache/artifacts/material_fonts:
// flutter test --update-goldens test/features/governance/governance_screenshots_test.dart
// The proposals are synthetic fixtures in the live response shape.
void main() {
  final fonts = Platform.environment['SCREENSHOT_FONTS'];

  Future<void> load(String family, String file) async {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(
          ByteData.sublistView(File('$fonts/$file').readAsBytesSync()),
        ),
      );
    await loader.load();
  }

  const advisory = AdvisoryProposalList(
    featureActive: true,
    observedAtHeight: 27412,
    total: 3,
    proposals: [
      AdvisoryProposal(
        id: 'adv-0000000000000001',
        title: 'Sample advisory proposal',
        summary: 'Synthetic text: should stations report every 10 minutes?',
        status: 'active',
        proposer: '0x0000000000000000000000000000000000000001',
        createdAtBlock: 27028,
        votingDeadline: 28148,
        yesVotes: 1,
        noVotes: 0,
        eligibleCount: 14,
        quorumMinVotes: 3,
        approvalPercent: 51,
        depositHeld: '100000000',
      ),
      AdvisoryProposal(
        id: 'adv-0000000000000002',
        title: 'Synthetic passed proposal',
        summary: 'Synthetic text for this screenshot.',
        status: 'passed',
        votingDeadline: 26000,
        finalizedAtBlock: 26001,
        yesVotes: 4,
        noVotes: 1,
        quorumMinVotes: 3,
        approvalPercent: 51,
      ),
      AdvisoryProposal(
        id: 'adv-0000000000000003',
        title: 'Synthetic proposal with too few votes',
        status: 'failed_quorum',
        votingDeadline: 25000,
        finalizedAtBlock: 25001,
        yesVotes: 1,
        noVotes: 0,
        quorumMinVotes: 3,
        approvalPercent: 51,
      ),
    ],
  );

  const proposal = ProposalModel(
    id: 'synthetic-1',
    title: 'Sample proposal',
    description: 'Synthetic text for this screenshot.',
    status: 'active',
  );

  const widths = {'phone-390': Size(390, 844), 'desktop-1280': Size(1280, 800)};
  for (final MapEntry(key: name, value: size) in widths.entries) {
    testWidgets('$name screenshots', (tester) async {
      await load('Roboto', 'Roboto-Regular.ttf');
      await load('MaterialIcons', 'MaterialIcons-Regular.otf');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app(Widget home) => ProviderScope(
        key: UniqueKey(),
        overrides: [
          appPreferencesStoreProvider.overrideWithValue(
            TestAppPreferencesStore(),
          ),
          governanceRepositoryProvider.overrideWithValue(
            FakeGovernanceRepository(advisory: advisory),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme.copyWith(
            textTheme: AppTheme.darkTheme.textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'Roboto'),
            child: home,
          ),
        ),
      );
      final screens = {
        'list': const ProposalListScreen(),
        'detail': ProposalDetailScreen(
          proposalId: advisory.proposals.first.id,
          initial: advisory.proposals.first,
        ),
        'vote': const VoteScreen(proposal: proposal),
      };
      for (final MapEntry(key: screen, value: widget) in screens.entries) {
        await tester.pumpWidget(app(widget));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../docs/screens/governance/$screen-$name.png',
          ),
        );
      }
    }, skip: fonts == null);
  }
}
