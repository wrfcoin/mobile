// A fake advisory governance API with the live response shape
// (GET https://wrfcoin.com/api/governance/advisory/proposals[/:id], 2026-11-15).
import 'package:dio/dio.dart';

/// The live "Welcome" proposal as the API returned it, field for field.
Map<String, dynamic> welcomeProposalJson() => <String, dynamic>{
  'approval_percent': 51,
  'created_at_block': 27028,
  'deposit_held': '100000000',
  'eligible_count': 14,
  'finalized_at_block': null,
  'id': 'adv-a75dae543f5f9e16',
  'kind': 'advisory',
  'no_votes': 0,
  'proposer': '0x2796629fd0f56360264b76f938b691a408181e89',
  'quorum_min_votes': 3,
  'status': 'active',
  'summary':
      'This is the first example proposal on the WRFCoin testnet. It changes '
      'nothing; it shows how proposing and voting work.',
  'title': 'Welcome to Wrfcoin Governance',
  'voting_deadline': 28148,
  'yes_votes': 1,
};

Map<String, dynamic> syntheticProposalJson(int n, {String status = 'active'}) =>
    <String, dynamic>{
      ...welcomeProposalJson(),
      'id': 'adv-${n.toRadixString(16).padLeft(16, '0')}',
      'title': 'Synthetic proposal $n',
      'summary': 'Synthetic summary $n.',
      'status': status,
    };

const Map<String, dynamic> limitsJson = <String, dynamic>{
  'approval_percent': 51,
  'chain_id': '888',
  'deposit': '100000000',
  'max_active_per_proposer': 1,
  'max_active_proposals': 20,
  'max_summary_bytes': 1024,
  'max_title_bytes': 160,
  'min_voter_spendable': '100000000',
  'network_id': 'testnet',
  'quorum_min_votes': 3,
  'voting_period_blocks': 1120,
};

/// Serves [proposals] in pages the way the backend does. Records every
/// request as "METHOD path?query".
class FakeAdvisoryApi {
  FakeAdvisoryApi(
    this.proposals, {
    this.featureActive = true,
    this.observedAtHeight = 27412,
    this.failAtOffset,
    this.alwaysMore = false,
    this.listStatus,
    this.detailStatus,
  });

  final List<Map<String, dynamic>> proposals;
  final bool featureActive;
  final int observedAtHeight;
  final int? failAtOffset;
  final bool alwaysMore;

  /// When set, the list answers this HTTP status with an error body.
  final int? listStatus;
  final int? detailStatus;
  final List<String> calls = <String>[];

  Dio dio() {
    final dio = Dio(BaseOptions(baseUrl: 'https://wrfcoin.com/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final q = options.uri.query;
          calls.add(
            '${options.method} ${options.uri.path}${q.isEmpty ? '' : '?$q'}',
          );
          final path = options.uri.path;
          if (path == '/api/governance/advisory/proposals') {
            final offset = options.queryParameters['offset'] as int;
            final limit = options.queryParameters['limit'] as int;
            if (listStatus != null || offset == failAtOffset) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: listStatus ?? 503,
                    data: {'success': false, 'error': 'Node unavailable'},
                  ),
                ),
              );
              return;
            }
            final end = alwaysMore
                ? offset + limit
                : (offset + limit).clamp(0, proposals.length);
            final page = alwaysMore
                ? [
                    for (var n = offset; n < end; n++)
                      syntheticProposalJson(n + 1),
                  ]
                : proposals.sublist(offset.clamp(0, proposals.length), end);
            final total = alwaysMore ? 999999 : proposals.length;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'success': true,
                  'featureActive': featureActive,
                  'observedAtHeight': observedAtHeight,
                  'count': page.length,
                  'total': total,
                  'offset': offset,
                  'limit': limit,
                  'hasMore': offset + page.length < total,
                  'proposals': page,
                  'limits': limitsJson,
                },
              ),
            );
            return;
          }
          final m = RegExp(
            r'^/api/governance/advisory/proposals/(adv-[0-9a-f]{16})$',
          ).firstMatch(path);
          if (m != null) {
            final found = proposals.where((p) => p['id'] == m.group(1));
            if (detailStatus != null || found.isEmpty) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: detailStatus ?? 404,
                    data: {
                      'success': false,
                      'error': {
                        'message': 'no advisory proposal with this id',
                        'code': 'CORE4_ERROR',
                      },
                    },
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'success': true,
                  'observedAtHeight': observedAtHeight,
                  'proposal': found.first,
                  'limits': limitsJson,
                },
              ),
            );
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: options, statusCode: 404),
            ),
          );
        },
      ),
    );
    return dio;
  }
}
