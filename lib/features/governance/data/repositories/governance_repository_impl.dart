import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/dio_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/formatting/reported_amount.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/api/api_response.dart';
import '../../../../services/crypto/advisory_action_signing.dart';
import '../../../../services/crypto/governance_vote_signing.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/observability/app_logger.dart';
import '../models/advisory_proposal.dart';
import '../models/advisory_vote.dart';
import '../models/proposal_model.dart';

final governanceRepositoryProvider = Provider<GovernanceRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return GovernanceRepository(
    api.dio,
    logger: ref.watch(appLoggerProvider),
    signer: GovernanceVoteSigner(keyManager: ref.watch(keyManagerProvider)),
    advisorySigner: AdvisoryActionSigner(
      keyManager: ref.watch(keyManagerProvider),
    ),
    ensureAuthenticated: api.ensureWalletSession,
  );
});

class GovernanceRepository {
  final Dio _dio;
  final AppLogger? _logger;
  final GovernanceVoteSigner? _signer;
  final Future<bool> Function()? _ensureAuthenticated;
  final AdvisoryActionSigner? _advisorySigner;

  GovernanceRepository(
    this._dio, {
    this._logger,
    this._signer,
    this._ensureAuthenticated,
    this._advisorySigner,
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

  /// The app wallet that would vote on advisory proposals. No unlock prompt.
  Future<AdvisoryVoter> advisoryVoter() async {
    final signer = _advisorySigner;
    if (signer == null) {
      return const AdvisoryVoter(address: null, canSign: false);
    }
    return signer.voter();
  }

  /// Whether [address] may vote on advisory proposal [id], and its nonce
  /// (`GET /governance/advisory/proposals/:id/eligibility?address=`).
  Future<Either<Failure, AdvisoryEligibility>> getAdvisoryEligibility(
    String id,
    String address,
  ) async {
    final a = address.trim().toLowerCase();
    if (!isAdvisoryProposalId(id)) {
      return const Left(ValidationFailure('Not an advisory proposal id.'));
    }
    if (!RegExp(r'^0x[0-9a-f]{40}$').hasMatch(a)) {
      return const Left(ValidationFailure('Not a wallet address.'));
    }
    try {
      final response = await _dio.get(
        ApiConstants.advisoryEligibility(id),
        queryParameters: <String, dynamic>{'address': a},
      );
      return Right(AdvisoryEligibility.fromJson(response.data));
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (_) {
      return const Left(
        ServerFailure('The vote check came back in an unexpected form.'),
      );
    }
  }

  /// Votes on an advisory proposal with the app's own wallet key, as the
  /// website does (frontend AdvisoryVoteButtons): read eligibility fresh (it
  /// carries the nonce), unlock the key with the device prompt, sign core4
  /// `advisory_action_message`, and POST the `SignedAdvisoryAction` to the
  /// relay. Nothing is sent without the unlock. The recovery phrase is never
  /// read.
  Future<Either<AdvisoryRefusal, AdvisorySubmitted>> voteAdvisory({
    required String proposalId,
    required bool approve,
    int? createdAtBlock,
  }) async {
    if (!isAdvisoryProposalId(proposalId)) {
      return const Left(
        AdvisoryRefusal(AdvisoryRefusalKind.other, 'Not an advisory proposal.'),
      );
    }
    final ready = await _readySigner('vote');
    if (ready case Left(value: final refusal)) return Left(refusal);
    final (signer, address) = ready.getOrElse(
      (_) => throw StateError('unreachable'),
    );

    final eligibility = await getAdvisoryEligibility(proposalId, address);
    final AdvisoryEligibility e;
    switch (eligibility) {
      case Left(value: final failure):
        return Left(
          AdvisoryRefusal(
            AdvisoryRefusalKind.network,
            failure.message.isNotEmpty
                ? failure.message
                : 'Could not check this vote. Try again in a minute.',
          ),
        );
      case Right(value: final value):
        e = value;
    }
    final refusal = e.refusalFor(createdAtBlock: createdAtBlock);
    if (refusal != null) return Left(refusal);

    return _signAndRelay(
      signer,
      AdvisoryVote(proposalId: proposalId, approve: approve),
      e.nextNonce!,
    );
  }

  /// The app wallet, if it can sign; otherwise why not ([verb] is "vote" or
  /// "propose").
  Future<Either<AdvisoryRefusal, (AdvisoryActionSigner, String)>> _readySigner(
    String verb,
  ) async {
    final signer = _advisorySigner;
    if (signer == null) {
      return Left(
        AdvisoryRefusal(
          AdvisoryRefusalKind.cantSign,
          "This wallet type can't $verb yet.",
        ),
      );
    }
    final voter = await signer.voter();
    final address = voter.address;
    if (address == null) {
      return Left(
        AdvisoryRefusal(
          AdvisoryRefusalKind.noWallet,
          'Create or import a wallet in the app to $verb.',
        ),
      );
    }
    if (!voter.canSign) {
      return Left(
        AdvisoryRefusal(
          AdvisoryRefusalKind.cantSign,
          "This wallet type can't $verb yet.",
        ),
      );
    }
    return Right((signer, address));
  }

  /// Unlocks, signs [action] at [nonce] and POSTs it to the relay once.
  Future<Either<AdvisoryRefusal, AdvisorySubmitted>> _signAndRelay(
    AdvisoryActionSigner signer,
    AdvisoryAction action,
    int nonce,
  ) async {
    final Map<String, dynamic> body;
    try {
      body = await signer.sign(action, nonce);
    } on AdvisoryUnlockCancelled {
      return const Left(
        AdvisoryRefusal(
          AdvisoryRefusalKind.unlockCancelled,
          'Unlock cancelled. Nothing was sent.',
        ),
      );
    } on AdvisorySigningUnavailable catch (x) {
      return Left(AdvisoryRefusal(AdvisoryRefusalKind.cantSign, x.message));
    }

    try {
      final response = await _dio.post(
        ApiConstants.advisoryActions,
        data: body,
        options: Options(
          // The edge admits exactly this Content-Type (no charset).
          contentType: 'application/json',
          // A signed vote is sent once; a retry would only be refused.
          extra: <String, dynamic>{'noRetry': true, 'noAuthRetry': true},
        ),
      );
      final data = response.data;
      String? text(String k) =>
          data is Map && data[k] is String ? data[k] as String : null;
      return Right(
        AdvisorySubmitted(
          txId: text('txId'),
          proposalId: text('proposalId'),
          nonce: nonce,
        ),
      );
    } on DioException catch (x) {
      return Left(describeAdvisoryRelayError(x, afterSigning: action));
    } catch (_) {
      return Left(_unknownOutcome(action));
    }
  }

  /// Proposes an advisory text with the app's own wallet key, as the
  /// website's propose form does: text rules first, then a balance check
  /// (the 1 WRF deposit; the advisory transaction pays no fee), the account
  /// nonce (`GET /governance/advisory/accounts/:address/nonce`), the device
  /// unlock, the signature and one POST to the relay.
  Future<Either<AdvisoryRefusal, AdvisorySubmitted>> proposeAdvisory({
    required String title,
    required String summary,
  }) async {
    final problem =
        advisoryTextProblem(AdvisoryTextField.title, title) ??
        advisoryTextProblem(AdvisoryTextField.summary, summary);
    if (problem != null) {
      return Left(AdvisoryRefusal(AdvisoryRefusalKind.invalidText, problem));
    }
    final ready = await _readySigner('propose');
    if (ready case Left(value: final refusal)) return Left(refusal);
    final (signer, address) = ready.getOrElse(
      (_) => throw StateError('unreachable'),
    );

    // Refuse before the unlock when the public balance read says the wallet
    // can't hold the deposit. If the read is unavailable the node decides.
    final balance = await _publicBalanceUnits(address);
    if (balance != null && balance < advisoryDepositUnits) {
      return const Left(AdvisoryRefusal.insufficientBalance);
    }

    final int nonce;
    try {
      final response = await _dio.get(ApiConstants.advisoryNonce(address));
      final data = response.data;
      final n = data is Map ? data['nonce'] : null;
      if (n is! int || n < 0 || n > advisoryMaxNonce) {
        throw const FormatException('nonce');
      }
      nonce = n;
    } on DioException catch (x) {
      final r = describeAdvisoryRelayError(x);
      return Left(
        r.kind == AdvisoryRefusalKind.other
            ? const AdvisoryRefusal(
                AdvisoryRefusalKind.network,
                "Couldn't read this wallet's nonce. Try again in a minute.",
              )
            : r,
      );
    } catch (_) {
      return const Left(
        AdvisoryRefusal(
          AdvisoryRefusalKind.network,
          "Couldn't read this wallet's nonce. Try again in a minute.",
        ),
      );
    }
    return _signAndRelay(
      signer,
      AdvisoryPropose(title: title, summary: summary),
      nonce,
    );
  }

  /// Base units from `GET /public/balance/0x<address>`, or null if the read
  /// is unavailable or not for this address.
  Future<BigInt?> _publicBalanceUnits(String address) async {
    try {
      final response = await _dio.get(
        ApiConstants.publicBalance(address.substring(2)),
      );
      final data = response.data;
      if (data is! Map ||
          (data['address'] as Object?)?.toString().toLowerCase() != address) {
        return null;
      }
      final b = data['balance'];
      return b is String && RegExp(r'^\d+$').hasMatch(b)
          ? BigInt.parse(b)
          : null;
    } catch (_) {
      return null;
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
        ValidationFailure('Advisory proposals are voted with voteAdvisory.'),
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

/// The relay's and the node's refusals in plain words (website
/// `describeAdvisoryError`, plus plain words for the node's known vote
/// refusals: already voted, not eligible, voting closed).
///
/// [afterSigning] is the action when [e] came from the POST of a signed
/// action. Then a timeout after connecting, a lost answer or a gateway
/// error means the outcome is unknown, not failed: the relay may have
/// passed it to the node.
AdvisoryRefusal describeAdvisoryRelayError(
  DioException e, {
  AdvisoryAction? afterSigning,
}) {
  final response = e.response;
  if (response == null) {
    final notSent = const {
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.badCertificate,
    }.contains(e.type);
    if (afterSigning != null && !notSent) return _unknownOutcome(afterSigning);
    return AdvisoryRefusal(
      AdvisoryRefusalKind.network,
      afterSigning != null
          ? 'Could not reach the network. Nothing was sent. Check your '
                'connection and try again.'
          : 'Could not reach the network. Check your connection and try again.',
    );
  }
  final status = response.statusCode ?? 0;
  final data = response.data;
  String? code;
  String? message;
  if (data is Map) {
    final err = data['error'];
    if (err is Map) {
      if (err['code'] is String) code = err['code'] as String;
      if (err['message'] is String) message = err['message'] as String;
    } else if (err is String) {
      message = err;
    }
    if (code == null && data['code'] is String) code = data['code'] as String;
  }
  final text = message ?? '';
  if (code == 'RATE_LIMITED' || status == 429 || text.contains('Too many')) {
    return const AdvisoryRefusal(
      AdvisoryRefusalKind.rateLimited,
      'Too many tries. Wait a few minutes and try again.',
    );
  }
  if (code == 'FEATURE_NOT_ACTIVE') {
    return const AdvisoryRefusal(
      AdvisoryRefusalKind.notActive,
      'Advisory voting is not on in the network yet.',
    );
  }
  if (status == 404 && code == 'NOT_FOUND') {
    return const AdvisoryRefusal(
      AdvisoryRefusalKind.relayOff,
      'Voting is switched off on the server right now. Nothing was sent.',
    );
  }
  if (code != null &&
      RegExp(r'ADVISORY|REFUSED|MEMPOOL').hasMatch(code) &&
      text.isNotEmpty) {
    final why = text.replaceFirst(
      RegExp(r'^.*SP_ADVISORY_GOVERNANCE_REFUSED:\s*'),
      '',
    );
    if (why.contains('already has an active proposal')) {
      return const AdvisoryRefusal(
        AdvisoryRefusalKind.activeProposal,
        'This wallet already has a proposal open. It can propose again once '
        'that one is decided.',
      );
    }
    if (why.contains('maximum number of active proposals')) {
      return const AdvisoryRefusal(
        AdvisoryRefusalKind.tooManyProposals,
        'The network already has the most open proposals it allows. Try again '
        'when one is decided.',
      );
    }
    if (RegExp(
      'insufficient spendable balance',
      caseSensitive: false,
    ).hasMatch(why)) {
      return AdvisoryRefusal.insufficientBalance;
    }
    if (why.contains('security key') || why.contains('allowlist')) {
      return const AdvisoryRefusal(
        AdvisoryRefusalKind.depositBlocked,
        "This wallet's spending guard (security key or send allowlist) stops "
        'it paying the proposal deposit.',
      );
    }
    if (why.contains('already voted')) {
      return const AdvisoryRefusal(
        AdvisoryRefusalKind.alreadyVoted,
        'This wallet already voted on this proposal.',
      );
    }
    if (why.contains('held under 1 WRF')) return AdvisoryRefusal.notEligible;
    if (why.contains('voting period has ended') ||
        why.contains('proposal is not active')) {
      return const AdvisoryRefusal(
        AdvisoryRefusalKind.votingClosed,
        'Voting on this proposal has closed.',
      );
    }
    final short = why.length > 160 ? why.substring(0, 160) : why;
    return AdvisoryRefusal(
      AdvisoryRefusalKind.refused,
      'The network refused it: $short',
    );
  }
  // A gateway or upstream error after a signed action was handed over: the
  // node may have taken it (backend UPSTREAM_ERROR, an edge 502/503/504).
  if (afterSigning != null &&
      (code == 'UPSTREAM_ERROR' ||
          status == 502 ||
          status == 503 ||
          status == 504 ||
          (status >= 500 && code == null))) {
    return _unknownOutcome(afterSigning);
  }
  if (text.isNotEmpty && text.length < 160) {
    return AdvisoryRefusal(AdvisoryRefusalKind.other, text);
  }
  return const AdvisoryRefusal(
    AdvisoryRefusalKind.other,
    'Could not send that. Try again in a minute.',
  );
}

AdvisoryRefusal _unknownOutcome(AdvisoryAction action) => AdvisoryRefusal(
  AdvisoryRefusalKind.unknown,
  action is AdvisoryVote ? advisoryVoteUnknownNote : advisoryProposeUnknownNote,
);
