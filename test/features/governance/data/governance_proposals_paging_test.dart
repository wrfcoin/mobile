// The older proposal list (no longer shown by the app; the governance
// screen reads the advisory list) used to stop at the first 20 (one page of the
// governance list). These tests serve more than 20 proposals across pages
// from a fake API and check that the app reads every page, with the same
// `limit`/`offset` parameters as the website (frontend PR #102), and that a
// broken API cannot make it loop forever.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';

Map<String, dynamic> _proposal(int n) => <String, dynamic>{
  'id': 'prop-$n',
  'title': 'Proposal number $n',
  'description': 'Synthetic proposal $n.',
  'proposalType': 'platform_upgrade',
  'status': 'active',
  'votesFor': 1,
  'votesAgainst': 0,
  'votesAbstain': 0,
};

/// A fake backend list endpoint over [total] proposals. Mirrors the backend:
/// `{ success, count, total, offset, limit, hasMore, proposals }`.
class _FakeGovernanceApi {
  _FakeGovernanceApi(
    this.total, {
    this.ignoreOffset = false,
    this.alwaysMore = false,
    this.failAtOffset,
    this.sendHasMore = true,
    this.sendTotal = true,
  });

  final int total;
  final bool ignoreOffset;
  final bool alwaysMore;
  final int? failAtOffset;
  final bool sendHasMore;
  final bool sendTotal;
  final List<Map<String, dynamic>> queries = <Map<String, dynamic>>[];

  Dio dio() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, ApiConstants.proposals);
          queries.add(Map<String, dynamic>.from(options.queryParameters));
          final limit = options.queryParameters['limit'] as int;
          final offset = ignoreOffset
              ? 0
              : options.queryParameters['offset'] as int;
          if (offset == failAtOffset) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
            return;
          }
          final end = alwaysMore
              ? offset + limit
              : (offset + limit).clamp(0, total);
          final page = <Map<String, dynamic>>[
            for (var n = offset; n < end; n++) _proposal(n + 1),
          ];
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{
                'success': true,
                'count': page.length,
                if (sendTotal) 'total': alwaysMore ? 999999 : total,
                'offset': offset,
                'limit': limit,
                if (sendHasMore) 'hasMore': alwaysMore || end < total,
                'proposals': page,
              },
            ),
          );
        },
      ),
    );
    return dio;
  }
}

void main() {
  group('GovernanceRepository.getProposals paging', () {
    test('reads all 45 proposals across 3 pages of limit=20', () async {
      final api = _FakeGovernanceApi(45);
      final result = await GovernanceRepository(api.dio()).getProposals();

      final proposals = result.getOrElse((f) => fail('Expected list, got $f'));
      expect(proposals, hasLength(45));
      expect(proposals.first.id, 'prop-1');
      expect(proposals.last.id, 'prop-45');
      expect(api.queries, <Map<String, dynamic>>[
        {'limit': 20, 'offset': 0},
        {'limit': 20, 'offset': 20},
        {'limit': 20, 'offset': 40},
      ]);
    });

    test('exactly 20 proposals is one request', () async {
      final api = _FakeGovernanceApi(20);
      final result = await GovernanceRepository(api.dio()).getProposals();

      expect(result.getOrElse((f) => fail('$f')), hasLength(20));
      expect(api.queries, hasLength(1));
    });

    test('without hasMore it uses total, then a short page', () async {
      final byTotal = _FakeGovernanceApi(41, sendHasMore: false);
      final r1 = await GovernanceRepository(byTotal.dio()).getProposals();
      expect(r1.getOrElse((f) => fail('$f')), hasLength(41));
      expect(byTotal.queries, hasLength(3));

      final byShortPage = _FakeGovernanceApi(
        41,
        sendHasMore: false,
        sendTotal: false,
      );
      final r2 = await GovernanceRepository(byShortPage.dio()).getProposals();
      expect(r2.getOrElse((f) => fail('$f')), hasLength(41));
      expect(byShortPage.queries, hasLength(3));
    });

    test('an API that ignores offset stops after the repeated page', () async {
      final api = _FakeGovernanceApi(100, ignoreOffset: true);
      final result = await GovernanceRepository(api.dio()).getProposals();

      expect(result.getOrElse((f) => fail('$f')), hasLength(20));
      expect(api.queries, hasLength(2));
    });

    test('an API that always says hasMore is capped', () async {
      final api = _FakeGovernanceApi(0, alwaysMore: true);
      final result = await GovernanceRepository(api.dio()).getProposals();

      expect(
        result.getOrElse((f) => fail('$f')),
        hasLength(
          GovernanceRepository.maxProposalPages *
              GovernanceRepository.proposalPageSize,
        ),
      );
      expect(api.queries, hasLength(GovernanceRepository.maxProposalPages));
    });

    test('a failed later page keeps the pages already read', () async {
      final api = _FakeGovernanceApi(45, failAtOffset: 20);
      final result = await GovernanceRepository(api.dio()).getProposals();

      expect(result.getOrElse((f) => fail('$f')), hasLength(20));
    });

    test('a failed first page is still an error', () async {
      final api = _FakeGovernanceApi(45, failAtOffset: 0);
      final result = await GovernanceRepository(api.dio()).getProposals();

      expect(result.isLeft(), isTrue);
    });
  });
}
