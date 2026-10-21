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

  Future<Either<Failure, List<ProposalModel>>> getProposals() async {
    try {
      final response = await _dio.get(ApiConstants.proposals);
      // Backend returns { success, count, proposals: [...] } — extract the list.
      final payload = response.data as Map<String, dynamic>;
      final list =
          (payload['proposals'] ?? payload['data'] ?? []) as List<dynamic>;
      // One unreadable item is skipped and logged; it must not blank the list.
      final proposals = <ProposalModel>[];
      for (var i = 0; i < list.length; i++) {
        try {
          proposals.add(ProposalModel.fromApiJson(list[i]));
        } on Object catch (e) {
          _logger?.warning(
            'governance_proposal_skipped',
            fields: <String, dynamic>{'index': i, 'error': e.toString()},
          );
        }
      }
      return Right(proposals);
    } on DioException catch (e) {
      return Left(DioErrorMapper.map(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
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
