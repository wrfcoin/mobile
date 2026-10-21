import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';

/// A core4 `GovernanceProposalRecord` exactly as serde serializes it and the
/// backend forwards it (core4 shared-protocol/src/blockchain/state.rs;
/// launch_api routes/governance.rs list_governance_proposals): snake_case,
/// no title/description/created time, PascalCase enums, Address as a byte
/// array, deadline as a block height.
Map<String, dynamic> core4Record({
  String id = 'gov-000001',
  String status = 'Active',
}) => <String, dynamic>{
  'id': id,
  'proposer': List<int>.filled(20, 7),
  'update': <String, dynamic>{'EmissionRate': 5},
  'proposal_class': 'ConstitutionalAmendment',
  'yes_votes': 1200,
  'no_votes': 300,
  'quorum_percent': 40,
  'approval_percent': 67,
  'eligible_voting_power': 5000,
  'eligible_voting_power_by_voter': <String, dynamic>{},
  'deposit': 1000000000,
  'voting_deadline': 21400,
  'status': status,
  'finalized_at_block': null,
  'execution_error': null,
  'votes_by_voter': <String, dynamic>{
    '0xabc': <String, dynamic>{
      'approve': true,
      'voting_power': 1200,
      'cast_at_block': 21105,
    },
  },
};

class _MemorySink implements LogSink {
  final entries = <AppLogEntry>[];
  @override
  void write(AppLogEntry entry) => entries.add(entry);
}

GovernanceRepository _repoReturning(Object? data, {AppLogger? logger}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) =>
          handler.resolve(Response(requestOptions: options, data: data)),
    ),
  );
  return GovernanceRepository(dio, logger: logger);
}

void main() {
  group('ProposalModel.fromApiJson (core4 native record)', () {
    test('maps a real-shaped core4 record with display fallbacks', () {
      final p = ProposalModel.fromApiJson(core4Record());
      expect(p.id, 'gov-000001');
      expect(p.title, 'Proposal gov-000001');
      expect(p.description, 'On-chain parameter update: EmissionRate = 5');
      expect(p.proposalType, 'constitutional_amendment');
      expect(p.status, 'active');
      expect(p.votesFor, 1200);
      expect(p.votesAgainst, 300);
      expect(p.votesAbstain, 0);
      expect(p.votingDeadlineBlock, 21400);
      expect(p.finalizedAtBlock, isNull);
      // core4 records no wall-clock creation time; none is invented.
      expect(p.createdAt, isNull);
    });

    test('maps every core4 status variant to snake_case', () {
      const expected = {
        'Active': 'active',
        'Executed': 'executed',
        'Rejected': 'rejected',
        'FailedQuorum': 'failed_quorum',
        'FailedExecution': 'failed_execution',
      };
      expected.forEach((core4, mobile) {
        expect(
          ProposalModel.fromApiJson(core4Record(status: core4)).status,
          mobile,
          reason: core4,
        );
      });
    });

    test('reads finalized block and a bare or struct update variant', () {
      final finalized = core4Record(status: 'Executed')
        ..['finalized_at_block'] = 21500
        ..['update'] = <String, dynamic>{
          'StakeRequired': <String, dynamic>{'amount': 10},
        };
      final p = ProposalModel.fromApiJson(finalized);
      expect(p.finalizedAtBlock, 21500);
      expect(
        p.description,
        'On-chain parameter update: StakeRequired = {amount: 10}',
      );

      final bare = core4Record()..['update'] = 'SomeUnitVariant';
      expect(
        ProposalModel.fromApiJson(bare).description,
        'On-chain parameter update: SomeUnitVariant',
      );
      final none = core4Record()..remove('update');
      expect(
        ProposalModel.fromApiJson(none).description,
        'No description on chain.',
      );
    });

    test('legacy camelCase fields still win', () {
      final p = ProposalModel.fromApiJson(<String, dynamic>{
        'id': 'prop-1',
        'title': 'Upgrade Consensus',
        'description': 'Reduce block time to 6s.',
        'proposalType': 'platform_upgrade',
        'status': 'passed',
        'votesFor': 80,
        'votesAgainst': 15,
        'votesAbstain': 5,
        'createdAt': '2026-09-01T00:00:00Z',
      });
      expect(p.title, 'Upgrade Consensus');
      expect(p.description, 'Reduce block time to 6s.');
      expect(p.proposalType, 'platform_upgrade');
      expect(p.status, 'passed');
      expect(p.votesAbstain, 5);
      expect(p.createdAt, '2026-09-01T00:00:00Z');
    });

    test('blank title/description fall back rather than render empty', () {
      final p = ProposalModel.fromApiJson(
        core4Record()
          ..['title'] = '  '
          ..['description'] = '',
      );
      expect(p.title, 'Proposal gov-000001');
      expect(p.description, startsWith('On-chain parameter update'));
    });

    test('an item without a usable id is a FormatException', () {
      for (final bad in <Object?>[
        null,
        'gov-1',
        <String, dynamic>{'title': 'no id'},
        <String, dynamic>{'id': ''},
        <String, dynamic>{'id': <String>[]},
      ]) {
        expect(
          () => ProposalModel.fromApiJson(bad),
          throwsA(isA<FormatException>()),
          reason: '$bad',
        );
      }
    });
  });

  group('GovernanceRepository.getProposals tolerance', () {
    test('a nonempty core4 page parses', () async {
      final repo = _repoReturning(<String, dynamic>{
        'success': true,
        'count': 2,
        'total': 2,
        'offset': 0,
        'limit': 100,
        'hasMore': false,
        'proposals': [
          core4Record(),
          core4Record(id: 'gov-000002', status: 'Rejected'),
        ],
      });
      final result = await repo.getProposals();
      final proposals = result.getOrElse(
        (f) => fail('expected proposals, got $f'),
      );
      expect(proposals.map((p) => p.id), ['gov-000001', 'gov-000002']);
      expect(proposals[1].status, 'rejected');
    });

    test('a malformed item is skipped and logged, not fatal', () async {
      final sink = _MemorySink();
      final repo = _repoReturning(<String, dynamic>{
        'success': true,
        'proposals': [
          core4Record(),
          <String, dynamic>{'title': 'no id'},
          'not an object',
          core4Record(id: 'gov-000003'),
        ],
      }, logger: AppLogger(sinks: [sink], verbose: true));
      final result = await repo.getProposals();
      final proposals = result.getOrElse(
        (f) => fail('expected proposals, got $f'),
      );
      expect(proposals.map((p) => p.id), ['gov-000001', 'gov-000003']);
      final skipped = sink.entries
          .where((e) => e.event == 'governance_proposal_skipped')
          .map((e) => e.fields['index'])
          .toList();
      expect(skipped, [1, 2]);
    });

    test('an empty list stays OK', () async {
      final repo = _repoReturning(<String, dynamic>{
        'success': true,
        'count': 0,
        'total': 0,
        'offset': 0,
        'limit': 100,
        'hasMore': false,
        'proposals': <dynamic>[],
      });
      final result = await repo.getProposals();
      expect(
        result.getOrElse((f) => fail('expected empty list, got $f')),
        isEmpty,
      );
    });

    test('getProposal reads a bare core4 record', () async {
      final repo = _repoReturning(core4Record(id: 'gov-000009'));
      final result = await repo.getProposal('gov-000009');
      final p = result.getOrElse((f) => fail('expected proposal, got $f'));
      expect(p.title, 'Proposal gov-000009');
      expect(p.votingDeadlineBlock, 21400);
    });
  });
}
