/// Whether one wallet may vote on one advisory proposal, as the relay
/// reports it (`GET /api/governance/advisory/proposals/:id/eligibility`,
/// camelCase members, from core4's eligibility route).
class AdvisoryEligibility {
  const AdvisoryEligibility({
    required this.votingOpen,
    required this.eligible,
    required this.canVote,
    this.voted,
    this.reason,
    this.nextNonce,
  });

  final bool votingOpen;

  /// The wallet held at least 1 WRF spendable when the proposal was made.
  final bool eligible;
  final bool canVote;

  /// 'for', 'against' or null.
  final String? voted;

  /// core4's reason when [canVote] is false.
  final String? reason;

  /// The wallet's account nonce (null when the chain has no such account).
  final int? nextNonce;

  factory AdvisoryEligibility.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('eligibility is not an object');
    }
    final v = raw['voted'];
    final n = raw['nextNonce'];
    final r = raw['reason'];
    return AdvisoryEligibility(
      votingOpen: raw['votingOpen'] == true,
      eligible: raw['eligible'] == true,
      canVote: raw['canVote'] == true,
      voted: v == 'for' || v == 'against' ? v as String : null,
      reason: r is String ? r : null,
      nextNonce: n is int && n >= 0 ? n : null,
    );
  }

  /// Why this wallet can't vote, in plain words, or null if it can.
  AdvisoryRefusal? get refusal => refusalFor();

  /// [refusal], naming the block the proposal was created at (its balance
  /// snapshot) when the caller knows it.
  AdvisoryRefusal? refusalFor({int? createdAtBlock}) {
    if (canVote && nextNonce != null) return null;
    if (voted != null) {
      return AdvisoryRefusal(
        AdvisoryRefusalKind.alreadyVoted,
        'This wallet already voted $voted.',
      );
    }
    if (!votingOpen) {
      return const AdvisoryRefusal(
        AdvisoryRefusalKind.votingClosed,
        'Voting on this proposal has closed.',
      );
    }
    if (!eligible) return AdvisoryRefusal.notEligibleAt(createdAtBlock);
    final why = reason;
    return AdvisoryRefusal(
      AdvisoryRefusalKind.other,
      why != null && why.isNotEmpty
          ? "This wallet can't vote: $why."
          : "This wallet can't vote on this one.",
    );
  }
}

enum AdvisoryRefusalKind {
  alreadyVoted,
  notEligible,
  votingClosed,
  rateLimited,
  notActive,
  relayOff,
  unlockCancelled,
  cantSign,
  noWallet,
  refused,
  network,
  insufficientBalance,
  activeProposal,

  /// The signed action may or may not have reached the chain (the request
  /// timed out after sending, or the relay lost the node's answer). Never
  /// worded as "failed".
  unknown,
  tooManyProposals,
  invalidText,
  depositBlocked,
  other,
}

/// A vote that was not sent (or that the relay or node refused), with the
/// words to show. Wording follows the website (frontend AdvisoryActions
/// `describeAdvisoryError`) where it has words for the case.
class AdvisoryRefusal {
  const AdvisoryRefusal(this.kind, this.message);

  final AdvisoryRefusalKind kind;
  final String message;

  static const insufficientBalance = AdvisoryRefusal(
    AdvisoryRefusalKind.insufficientBalance,
    'This wallet has under 1 WRF it can spend. Proposing holds 1 WRF, so it '
    "can't propose yet. Nothing was sent.",
  );

  /// Only wallets that held at least 1 WRF spendable when a proposal was
  /// created can vote on it (core4 advisory governance snapshot).
  static const notEligible = AdvisoryRefusal(
    AdvisoryRefusalKind.notEligible,
    "This wallet can't vote on this proposal: it held less than 1 WRF when "
    'the proposal was created. It can vote on proposals created from now '
    'on, while it holds 1 WRF or more.',
  );

  /// [notEligible], naming the creation block when it is known.
  static AdvisoryRefusal notEligibleAt(int? createdAtBlock) =>
      createdAtBlock == null
      ? notEligible
      : AdvisoryRefusal(
          AdvisoryRefusalKind.notEligible,
          "This wallet can't vote on this proposal: it held less than 1 WRF "
          'when the proposal was created (block $createdAtBlock). It can '
          'vote on proposals created from now on, while it holds 1 WRF or '
          'more.',
        );

  @override
  String toString() => message;
}

/// What the relay said after taking a signed vote. "Sent" is not "counted":
/// it counts once it is in a block.
class AdvisorySubmitted {
  const AdvisorySubmitted({this.txId, this.proposalId, required this.nonce});

  final String? txId;

  /// The id the chain gives a new proposal (propose only).
  final String? proposalId;
  final int nonce;
}

/// Shown after the relay takes a vote (website `PENDING_NOTE`, shortened).
const String advisoryPendingNote =
    "Sent. It counts once it's in a block (blocks come about every 77 "
    'seconds). This page checks again by itself.';

/// Shown when a signed vote may or may not have reached the chain.
const String advisoryVoteUnknownNote =
    "We couldn't confirm your vote reached the network. It may still count. "
    "Don't vote again yet: this page checks again in about 2 minutes, and "
    "if it shows how you voted, it counted.";

/// Shown when a signed proposal may or may not have reached the chain.
const String advisoryProposeUnknownNote =
    "We couldn't confirm your proposal reached the network. It may still be "
    'made. Check the proposal list in about 2 minutes before proposing '
    'again.';
