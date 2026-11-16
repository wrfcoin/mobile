import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/advisory_proposal.dart';
import '../../data/repositories/governance_repository_impl.dart';

/// The advisory proposal list (chain 888). The older `/governance/proposals`
/// list is empty by design, so the app no longer reads it.
/// No automatic retry: a failure shows the error state with a Retry button,
/// so a down node is not polled in the background.
final advisoryProposalsProvider = FutureProvider<AdvisoryProposalList>((
  ref,
) async {
  final result = await ref
      .read(governanceRepositoryProvider)
      .getAdvisoryProposals();
  return result.fold((failure) => throw failure, (list) => list);
}, retry: (_, _) => null);

/// One advisory proposal, read fresh by id for the detail screen.
final advisoryProposalProvider =
    FutureProvider.family<AdvisoryProposalDetail, String>((ref, id) async {
      final result = await ref
          .read(governanceRepositoryProvider)
          .getAdvisoryProposal(id);
      return result.fold((failure) => throw failure, (detail) => detail);
    }, retry: (_, _) => null);
