// The app reads chain 888's advisory proposals, not the older list (empty by
// design). These run the repository against a fake API with the live shape.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/advisory_proposal.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';

import '../fixtures/advisory_api.dart';

void main() {
  group('getAdvisoryProposals', () {
    test('reads the live shape: one page, feature active, height', () async {
      final api = FakeAdvisoryApi([welcomeProposalJson()]);
      final result = await GovernanceRepository(api.dio())
          .getAdvisoryProposals();
      final list = result.getOrElse((f) => throw f);

      expect(api.calls, [
        'GET /api/governance/advisory/proposals?limit=20&offset=0',
      ]);
      expect(list.featureActive, isTrue);
      expect(list.observedAtHeight, 27412);
      expect(list.total, 1);
      expect(list.incomplete, isFalse);
      final p = list.proposals.single;
      expect(p.id, 'adv-a75dae543f5f9e16');
      expect(p.title, 'Welcome to Wrfcoin Governance');
      expect(p.status, 'active');
      expect(p.summary, startsWith('This is the first example proposal'));
      expect(p.yesVotes, 1);
      expect(p.noVotes, 0);
      expect(p.quorumMinVotes, 3);
      expect(p.approvalPercent, 51);
      expect(p.eligibleCount, 14);
      expect(p.createdAtBlock, 27028);
      expect(p.votingDeadline, 28148);
      expect(p.finalizedAtBlock, isNull);
      expect(p.depositDisplay, '1 WRF');
      expect(p.proposer, '0x2796629fd0f56360264b76f938b691a408181e89');
    });

    test(
      'pages past 20 with exactly limit=20&offset=n (the edge allowlist)',
      () async {
        final api = FakeAdvisoryApi([
          for (var n = 1; n <= 45; n++) syntheticProposalJson(n),
        ]);
        final list = (await GovernanceRepository(
          api.dio(),
        ).getAdvisoryProposals()).getOrElse((f) => throw f);
        expect(list.proposals, hasLength(45));
        expect(list.total, 45);
        expect(api.calls, [
          'GET /api/governance/advisory/proposals?limit=20&offset=0',
          'GET /api/governance/advisory/proposals?limit=20&offset=20',
          'GET /api/governance/advisory/proposals?limit=20&offset=40',
        ]);
      },
    );

    test('an API that always says "more" stops at the page bound', () async {
      final api = FakeAdvisoryApi(const [], alwaysMore: true);
      final list = (await GovernanceRepository(
        api.dio(),
      ).getAdvisoryProposals()).getOrElse((f) => throw f);
      expect(api.calls, hasLength(GovernanceRepository.maxProposalPages));
      expect(
        list.proposals,
        hasLength(
          GovernanceRepository.maxProposalPages *
              GovernanceRepository.proposalPageSize,
        ),
      );
    });

    test(
      'a failed later page keeps the first and marks it incomplete',
      () async {
        final api = FakeAdvisoryApi([
          for (var n = 1; n <= 30; n++) syntheticProposalJson(n),
        ], failAtOffset: 20);
        final list = (await GovernanceRepository(
          api.dio(),
        ).getAdvisoryProposals()).getOrElse((f) => throw f);
        expect(list.proposals, hasLength(20));
        expect(list.incomplete, isTrue);
      },
    );

    test('a failed first page is an error', () async {
      final api = FakeAdvisoryApi(const [], listStatus: 503);
      final result = await GovernanceRepository(api.dio())
          .getAdvisoryProposals();
      expect(result.isLeft(), isTrue);
    });

    test('an odd body is an error, not an empty list', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) => h.resolve(
              Response(requestOptions: o, statusCode: 200, data: 'Not found'),
            ),
          ),
        );
      final result = await GovernanceRepository(dio).getAdvisoryProposals();
      expect(result.isLeft(), isTrue);
    });

    test('feature not active and no proposals', () async {
      final api = FakeAdvisoryApi(const [], featureActive: false);
      final list = (await GovernanceRepository(
        api.dio(),
      ).getAdvisoryProposals()).getOrElse((f) => throw f);
      expect(list.featureActive, isFalse);
      expect(list.proposals, isEmpty);
    });

    test('an unreadable item is skipped, not the whole list', () async {
      final api = FakeAdvisoryApi([
        welcomeProposalJson(),
        {'id': 7, 'title': 'integer id from the old list'},
      ]);
      final list = (await GovernanceRepository(
        api.dio(),
      ).getAdvisoryProposals()).getOrElse((f) => throw f);
      expect(list.proposals.map((p) => p.id), ['adv-a75dae543f5f9e16']);
    });
  });

  group('getAdvisoryProposal', () {
    test('reads one proposal by id with the observed height', () async {
      final api = FakeAdvisoryApi([welcomeProposalJson()]);
      final detail = (await GovernanceRepository(
        api.dio(),
      ).getAdvisoryProposal('adv-a75dae543f5f9e16')).getOrElse((f) => throw f);
      expect(api.calls, [
        'GET /api/governance/advisory/proposals/adv-a75dae543f5f9e16',
      ]);
      expect(detail.proposal.title, 'Welcome to Wrfcoin Governance');
      expect(detail.observedAtHeight, 27412);
    });

    test('an unknown id is an error', () async {
      final api = FakeAdvisoryApi([welcomeProposalJson()]);
      final result = await GovernanceRepository(api.dio())
          .getAdvisoryProposal('adv-0000000000000000');
      expect(result.isLeft(), isTrue);
    });

    test('a non-advisory id sends nothing', () async {
      final api = FakeAdvisoryApi([welcomeProposalJson()]);
      final result = await GovernanceRepository(api.dio())
          .getAdvisoryProposal('7');
      expect(result, isA<Left<Failure, AdvisoryProposalDetail>>());
      expect(api.calls, isEmpty);
    });
  });

  test('the older vote route refuses advisory ids and sends nothing', () async {
    final api = FakeAdvisoryApi([welcomeProposalJson()]);
    final result = await GovernanceRepository(api.dio())
        .vote(proposalId: 'adv-a75dae543f5f9e16', voteType: 'FOR');
    expect(result.isLeft(), isTrue);
    expect(api.calls, isEmpty);
  });

  group('display helpers', () {
    final p = AdvisoryProposal.fromJson(welcomeProposalJson());

    test('deadline: block plus an estimate at 77 s per block', () {
      // 28148 - 27412 = 736 blocks * 77 s = 56672 s = 15 h 44 min.
      expect(
        describeAdvisoryDeadline(p, 27412),
        'Voting ends at block 28148 (about 15 h 44 min from now)',
      );
      expect(describeAdvisoryDeadline(p, null), 'Voting ends at block 28148');
      expect(describeAdvisoryDeadline(p, 28200), 'Voting ended at block 28148');
    });

    test('a decided proposal names the block it was decided at', () {
      final decided = AdvisoryProposal.fromJson({
        ...welcomeProposalJson(),
        'status': 'passed',
        'finalized_at_block': 28149,
      });
      expect(
        describeAdvisoryDeadline(decided, 28200),
        'Decided at block 28149',
      );
    });

    test('status words match the website', () {
      expect(advisoryStatusLabel('active'), 'Voting');
      expect(advisoryStatusLabel('passed'), 'Passed (advisory)');
      expect(advisoryStatusLabel('rejected'), 'Rejected');
      expect(advisoryStatusLabel('failed_quorum'), 'Too few votes');
    });

    test('deposit note uses the proposal amount and quorum', () {
      expect(
        advisoryDepositNote(p),
        "Proposing holds 1 WRF from the proposer's wallet. It comes back when "
        'the vote is decided, and stays held if fewer than 3 wallets vote.',
      );
    });

    test('durations', () {
      expect(
        formatApproxDuration(const Duration(seconds: 30)),
        'under a minute',
      );
      expect(formatApproxDuration(const Duration(minutes: 5)), '5 min');
      expect(formatApproxDuration(const Duration(hours: 2)), '2 h');
      expect(formatApproxDuration(const Duration(hours: 50)), '2 d 2 h');
    });
  });
}
