import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/proposal_model.dart';
import '../../data/repositories/governance_repository_impl.dart';

final proposalsProvider =
    AsyncNotifierProvider<ProposalsNotifier, List<ProposalModel>>(
      ProposalsNotifier.new,
    );

class ProposalsNotifier extends AsyncNotifier<List<ProposalModel>> {
  @override
  Future<List<ProposalModel>> build() async {
    return _fetchProposals();
  }

  Future<List<ProposalModel>> _fetchProposals() async {
    final repo = ref.read(governanceRepositoryProvider);
    final result = await repo.getProposals();
    return result.fold((failure) => throw failure, (proposals) => proposals);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchProposals);
  }

  Future<void> vote({
    required String proposalId,
    required String voteType,
    String? reason,
  }) async {
    final repo = ref.read(governanceRepositoryProvider);
    final result = await repo.vote(
      proposalId: proposalId,
      voteType: voteType,
      reason: reason,
    );
    result.fold((failure) => throw failure, (_) => refresh());
  }
}
