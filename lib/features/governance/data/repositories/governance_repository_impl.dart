import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/dio_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/formatting/reported_amount.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/api/api_response.dart';
import '../../../../services/crypto/governance_vote_signing.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/observability/app_logger.dart';
import '../models/advisory_proposal.dart';
import '../models/proposal_model.dart';

final governanceRepositoryProvider = Provider<GovernanceRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return GovernanceRepository(
    api.dio,
    logger: ref.watch(appLoggerProvider),
    signer: GovernanceVoteSigner(keyManager: ref.watch(keyManagerProvider)),
    ensureAuthenticated: api.ensureWalletSession,
  );
});

class GovernanceRepository {
  final Dio _dio;
  final AppLogger? _logger;
  final GovernanceVoteSigner? _signer;
  final Future<bool> Function()? _ensureAuthenticated;

  GovernanceRepository(
    this._dio, {
    this._logger,
    this._signer,
    this._ensureAuthenticated,
  });

  /// Page size for the proposal list. Same as the website (frontend
  /// `GOVERNANCE_PAGE_SIZE`); the public edge admits `limit=<1..100>&offset=<n>`.
  static const int proposalPageSize = 20;

  /// Upper bound on pages read for one list load (1000 proposals), so an API
  /// that keeps saying "more" can never loop forever.
  static const int maxProposalPages = 50;

  /// Reads every page of `/governance/proposals?limit=20&offset=n` (the same
  /// endpoint and parameters as the website, frontend PR #102), not just the
  /// first 20. Stops when the backend says `hasMore: false`, when `total` is
  /// reached, on a short or empty page, on a page with nothing new, or after
  /// [maxProposalPages]. If a later page fails, the proposals already read are
  /// kept; only a failed first page is an error.
  Future<Either<Failure, List<ProposalModel>>> getProposals() async {
    final proposals = <ProposalModel>[];
    final seenIds = <String>{};
    var offset = 0;
    for (var page = 0; page < maxProposalPages; page++) {
      final Map<String, dynamic> payload;
      try {
        final response = await _dio.get(
          ApiConstants.proposals,
          queryParameters: <String, dynamic>{
            'limit': proposalPageSize,
            'offset': offset,
          },
        );
        // Backend returns { success, count, total, offset, limit, hasMore,
        // proposals: [...] }.
        payload = response.data as Map<String, dynamic>;
      } on DioException catch (e) {
        if (page == 0) return Left(DioErrorMapper.map(e));
        _logPageFailure(offset, e);
        break;
      } catch (e) {
        if (page == 0) return Left(ServerFailure(e.toString()));
        _logPageFailure(offset, e);
        break;
      }
      final list =
          (payload['proposals'] ?? payload['data'] ?? []) as List<dynamic>;
      var repeats = 0;
      // One unreadable item is skipped and logged; it must not blank the list.
      for (var i = 0; i < list.length; i++) {
        try {
          final proposal = ProposalModel.fromApiJson(list[i]);
          if (seenIds.add(proposal.id)) {
            proposals.add(proposal);
          } else {
            repeats++;
          }
        } on Object catch (e) {
          _logger?.warning(
            'governance_proposal_skipped',
            fields: <String, dynamic>{
              'index': offset + i,
              'error': e.toString(),
            },
          );
        }
      }
      final hasMore = payload['hasMore'];
      final total = payload['total'];
      offset += list.length;
      // An empty page, or a page of only proposals already read (an API that
      // ignores offset), ends the load.
      if (list.isEmpty || repeats == list.length) break;
      if (hasMore is bool) {
        if (!hasMore) break;
      } else if (total is int) {
        if (offset >= total) break;
      } else if (list.length < proposalPageSize) {
        break;
      }
    }
    return Right(proposals);
  }

  void _logPageFailure(int offset, Object error) {
    _logger?.warning(
      'governance_proposal_page_failed',
      fields: <String, dynamic>{'offset': offset, 'error': error.toString()},
    );
  }

  /// Reads every page of the advisory list (chain 888 `advisory_governance`,
  /// `GET /governance/advisory/proposals?limit=20&offset=n`, the same
  /// parameters and order as the website, which the public edge requires).
  /// Bounded like [getProposals]: stops on `hasMore: false`, at `total`, on a
  /// short, empty or all-repeat page, or after [maxProposalPages]. A failed
  /// later page keeps what was read and marks the list incomplete; only a
  /// failed first page is an error.
  Future<Either<Failure, AdvisoryProposalList>> getAdvisoryProposals() async {
    final proposals = <AdvisoryProposal>[];
    final seenIds = <String>{};
    var featureActive = false;
    int? observedAtHeight;
    int? total;
    var incomplete = false;
    var offset = 0;
    for (var page = 0; page < maxProposalPages; page++) {
      final Map<String, dynamic> payload;
      try {
        final response = await _dio.get(
          ApiConstants.advisoryProposals,
          queryParameters: <String, dynamic>{
            'limit': proposalPageSize,
            'offset': offset,
          },
        );
        final data = response.data;
        if (data is! Map || data['proposals'] is! List) {
          throw const FormatException('Unexpected advisory proposal list');
        }
        payload = Map<String, dynamic>.from(data);
      } on DioException catch (e) {
        if (page == 0) return Left(DioErrorMapper.map(e));
        _logPageFailure(offset, e);
        incomplete = true;
        break;
      } catch (e) {
        if (page == 0) {
          return const Left(
            ServerFailure(
              'The governance list came back in an unexpected form.',
            ),
          );
        }
        _logPageFailure(offset, e);
        incomplete = true;
        break;
      }
      if (page == 0) {
        featureActive = payload['featureActive'] == true;
        final h = payload['observedAtHeight'];
        observedAtHeight = h is int ? h : null;
      }
      final t = payload['total'];
      if (t is int && t >= 0) total = t;
      final list = payload['proposals'] as List<dynamic>;
      var repeats = 0;
      for (var i = 0; i < list.length; i++) {
        try {
          final proposal = AdvisoryProposal.fromJson(list[i]);
          if (seenIds.add(proposal.id)) {
            proposals.add(proposal);
          } else {
            repeats++;
          }
        } on Object catch (e) {
          _logger?.warning(
            'governance_advisory_proposal_skipped',
            fields: <String, dynamic>{
              'index': offset + i,
              'error': e.toString(),
            },
          );
        }
      }
      final hasMore = payload['hasMore'];
      offset += list.length;
      if (list.isEmpty || repeats == list.length) break;
      if (hasMore is bool) {
        if (!hasMore) break;
      } else if (t is int) {
        if (offset >= t) break;
      } else if (list.length < proposalPageSize) {
        break;
      }
    }
    return Right(
      AdvisoryProposalList(
        proposals: proposals,
        featureActive: featureActive,
        observedAtHeight: observedAtHeight,
        total: total,
        incomplete: incomplete,
      ),
    );
  }

  /// One advisory proposal by id (`GET /governance/advisory/proposals/:id`).
  Future<Either<Failure, AdvisoryProposalDetail>> getAdvisoryProposal(
    String id,
  ) async {
    if (!isAdvisoryProposalId(id)) {
      return const Left(ValidationFailure('Not an advisory proposal id.'));
    }
    try {
      final response = await _dio.get(ApiConstants.advisoryProposal(id));
      final data = response.data;
      if (data is! Map) {
        throw const FormatException('Unexpected advisory proposal');
      }
      final h = data['observedAtHeight'];
      return Right(
        AdvisoryProposalDetail(
          proposal: AdvisoryProposal.fromJson(data['proposal']),
          observedAtHeight: h is int ? h : null,
        ),
      );
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return const Left(
        ServerFailure('The proposal came back in an unexpected form.'),
      );
    }
  }

  Future<Either<Failure, ProposalModel>> getProposal(String id) async {
    try {
      final response = await _dio.get(ApiConstants.proposal(id));
      // Backend returns { success, proposal: {...} } — extract the proposal.
      final payload = response.data as Map<String, dynamic>;
      final proposal = payload['proposal'] ?? payload['data'] ?? payload;
      return Right(ProposalModel.fromApiJson(proposal));
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Map<String, dynamic>>> vote({
    required String proposalId,
    required String voteType,
    String? reason,
  }) async {
    // Advisory proposals are voted with a signed advisory action, never
    // through this older route (integer ids).
    if (isAdvisoryProposalId(proposalId)) {
      return const Left(
        ValidationFailure('Vote on advisory proposals at wrfcoin.com.'),
      );
    }
    try {
      final choice = voteType.toUpperCase();
      if (choice != 'FOR' && choice != 'AGAINST') {
        return const Left(ValidationFailure('Choose For or Against.'));
      }
      final signer = _signer;
      if (signer == null ||
          !await (_ensureAuthenticated?.call() ?? Future.value(false))) {
        return const Left(
          AuthFailure('Sign in with your wallet before voting.'),
        );
      }
      final signed = await signer.signVote(proposalId, choice == 'FOR');
      if (signed == null) {
        return const Left(
          AuthFailure('Authentication required to sign your vote.'),
        );
      }
      final response = await _dio.post(
        ApiConstants.vote(proposalId),
        data: {
          'voteType': choice,
          ...signed,
          if (reason?.isNotEmpty ?? false) 'reason': reason,
        },
      );
      return Right(response.data as Map<String, dynamic>);
    } on GovernanceSigningUnavailable catch (e) {
      return Left(SecurityFailure(e.message));
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Map<String, dynamic>>> getTreasuryInfo() async {
    try {
      final response = await _dio.get(ApiConstants.treasury);
      final payload = unwrapMapPayload(response.data);
      final treasury = payload['treasury'] is Map
          ? Map<String, dynamic>.from(payload['treasury'] as Map)
          : payload;
      final currency =
          treasury['currency']?.toString() ?? payload['currency']?.toString();
      return Right(<String, dynamic>{
        'balance': _normalizeBalance(treasury['balance'], currency),
        'amountUnits': treasury['amountUnits'] ?? payload['amountUnits'],
        'currency': currency,
        'lastUpdated':
            treasury['lastUpdated']?.toString() ??
            payload['lastUpdated']?.toString(),
      });
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  String? _normalizeBalance(dynamic value, String? currency) {
    // Do not turn floating-point wire amounts into supposedly exact strings.
    if (value is! String) return null;
    // Legacy responses can include their explicit currency in the value.
    // This compatibility path does not establish a display denomination.
    if (currency != null && currency.isNotEmpty) {
      final raw = value.trim();
      final suffix = ' $currency';
      if (raw.endsWith(suffix)) {
        value = raw.substring(0, raw.length - suffix.length);
      }
    }
    return reportedAmount(value);
  }
}
