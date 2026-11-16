import '../../../../core/utils/wrf_units.dart';

/// Advisory proposal ids are `adv-` plus 16 hex digits (core4
/// `advisory_governance`; backend `ADVISORY_ID_RE`).
final RegExp advisoryProposalIdPattern = RegExp(r'^adv-[0-9a-f]{16}$');

bool isAdvisoryProposalId(String id) => advisoryProposalIdPattern.hasMatch(id);

/// Chain 888 makes a block about every 77 s (block-heartbeat service). Used
/// only to estimate when a block height will be reached.
const Duration chainBlockInterval = Duration(seconds: 77);

/// One advisory proposal as the backend relays core4's record
/// (`GET /api/governance/advisory/proposals[/:id]`, snake_case members).
class AdvisoryProposal {
  const AdvisoryProposal({
    required this.id,
    required this.title,
    this.summary = '',
    this.kind = 'advisory',
    this.status = '',
    this.proposer,
    this.createdAtBlock,
    this.votingDeadline,
    this.finalizedAtBlock,
    this.yesVotes,
    this.noVotes,
    this.eligibleCount,
    this.quorumMinVotes,
    this.approvalPercent,
    this.depositHeld,
  });

  final String id;
  final String title;
  final String summary;
  final String kind;
  final String status;
  final String? proposer;
  final int? createdAtBlock;
  final int? votingDeadline;
  final int? finalizedAtBlock;
  final int? yesVotes;
  final int? noVotes;
  final int? eligibleCount;
  final int? quorumMinVotes;
  final int? approvalPercent;

  /// Base units (string, as the node sends them), e.g. "100000000" = 1 WRF.
  final String? depositHeld;

  bool get isActive => status == 'active';

  /// Throws [FormatException] for an item without an advisory id or title.
  factory AdvisoryProposal.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('proposal is not an object');
    final json = Map<String, dynamic>.from(raw);
    final id = json['id'];
    if (id is! String || !isAdvisoryProposalId(id)) {
      throw FormatException('not an advisory proposal id: $id');
    }
    final title = json['title'];
    if (title is! String) throw const FormatException('proposal has no title');
    int? count(String key) {
      final v = json[key];
      return v is int && v >= 0 ? v : null;
    }

    String? text(String key) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    return AdvisoryProposal(
      id: id,
      title: title,
      summary: text('summary') ?? text('body') ?? '',
      kind: text('kind') ?? 'advisory',
      status: text('status') ?? '',
      proposer: text('proposer'),
      createdAtBlock: count('created_at_block'),
      votingDeadline: count('voting_deadline'),
      finalizedAtBlock: count('finalized_at_block'),
      yesVotes: count('yes_votes'),
      noVotes: count('no_votes'),
      eligibleCount: count('eligible_count'),
      quorumMinVotes: count('quorum_min_votes'),
      approvalPercent: count('approval_percent'),
      depositHeld: text('deposit_held'),
    );
  }

  /// "1 WRF" for "100000000", or null when the value is missing or odd.
  String? get depositDisplay {
    final raw = depositHeld;
    if (raw == null) return null;
    final display = wrfBaseUnitsToDisplay(raw);
    return display == null ? null : '$display WRF';
  }
}

/// The advisory list across every page read, plus what the node reported.
class AdvisoryProposalList {
  const AdvisoryProposalList({
    required this.proposals,
    required this.featureActive,
    this.observedAtHeight,
    this.total,
    this.incomplete = false,
  });

  final List<AdvisoryProposal> proposals;

  /// The node reports `advisory_governance` active at the next block.
  final bool featureActive;
  final int? observedAtHeight;
  final int? total;

  /// A later page failed, so [proposals] is only the pages before it.
  final bool incomplete;
}

/// One proposal read by id, with the height the node answered at.
class AdvisoryProposalDetail {
  const AdvisoryProposalDetail({required this.proposal, this.observedAtHeight});

  final AdvisoryProposal proposal;
  final int? observedAtHeight;
}

/// Person-readable status, the same words as the website
/// (frontend PublicGovernancePage `ADVISORY_STATUS`).
String advisoryStatusLabel(String status) => switch (status) {
  'active' => 'Voting',
  'passed' => 'Passed (advisory)',
  'rejected' => 'Rejected',
  'failed_quorum' => 'Too few votes',
  '' => 'Unknown',
  _ => status,
};

/// The deadline as a block height plus an estimate at ~77 s per block from
/// the height the node reported. Without a reported height, only the block.
String describeAdvisoryDeadline(AdvisoryProposal p, int? observedAtHeight) {
  final finalized = p.finalizedAtBlock;
  if (finalized != null) return 'Decided at block $finalized';
  final deadline = p.votingDeadline;
  if (deadline == null) return 'Voting deadline not reported';
  if (observedAtHeight == null) return 'Voting ends at block $deadline';
  final remaining = deadline - observedAtHeight;
  if (remaining <= 0) return 'Voting ended at block $deadline';
  final eta = formatApproxDuration(chainBlockInterval * remaining);
  return 'Voting ends at block $deadline (about $eta from now)';
}

/// "8 h 13 min", "2 d 4 h", "5 min", "under a minute".
String formatApproxDuration(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return hours > 0 ? '$days d $hours h' : '$days d';
  if (d.inHours > 0) {
    return minutes > 0 ? '${d.inHours} h $minutes min' : '${d.inHours} h';
  }
  return '$minutes min';
}

/// Where a person votes until the app signs advisory votes itself. The
/// website's vote buttons are on the list page; its `/governance/public/:id`
/// page reads the older proposal list and does not know advisory ids.
const String advisoryVoteWebUrl = 'https://wrfcoin.com/governance/public';

/// The website's deposit note (frontend AdvisoryActions `DEPOSIT_NOTE`),
/// with the amount and quorum taken from the proposal when it has them.
String advisoryDepositNote(AdvisoryProposal p) {
  final amount = p.depositDisplay ?? '1 WRF';
  final quorum = p.quorumMinVotes ?? 3;
  return 'Proposing holds $amount from the proposer\'s wallet. It comes back '
      'when the vote is decided, and stays held if fewer than $quorum wallets '
      'vote.';
}
