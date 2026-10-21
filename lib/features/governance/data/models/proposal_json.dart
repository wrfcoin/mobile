/// Normalizes one governance proposal from the backend into the camelCase
/// shape [ProposalModel.fromJson] reads.
///
/// The backend forwards core4's `GovernanceProposalRecord` unchanged
/// (core4 shared-protocol/src/blockchain/state.rs; launch_api
/// routes/governance.rs). Those records are snake_case serde, carry no title,
/// description or creation time, use PascalCase status/class enums, and give
/// the deadline as a block height. Legacy camelCase fields still win when
/// present.
///
/// Throws [FormatException] when [raw] is not an object or has no usable id;
/// the list reader skips such items instead of failing the whole list.
Map<String, dynamic> normalizeProposalJson(Object? raw) {
  if (raw is! Map) {
    throw FormatException('proposal is not an object', raw);
  }
  final json = Map<String, dynamic>.from(raw);

  final rawId = json['id'];
  final id = switch (rawId) {
    final String s when s.trim().isNotEmpty => s,
    final int n => n.toString(),
    _ => throw FormatException('proposal has no id', rawId),
  };

  return <String, dynamic>{
    'id': id,
    'title': _nonEmptyString(json['title']) ?? 'Proposal $id',
    'description':
        _nonEmptyString(json['description']) ??
        _describeUpdate(json['update']) ??
        'No description on chain.',
    'proposalType':
        _nonEmptyString(json['proposalType']) ??
        _snakeEnum(json['proposal_class']) ??
        'standard',
    'status': _statusOf(json['status']) ?? 'active',
    'votingPeriod': _nonEmptyString(json['votingPeriod']),
    'createdAt': _nonEmptyString(json['createdAt']),
    'votesFor': _count(json['votesFor']) ?? _count(json['yes_votes']) ?? 0,
    'votesAgainst':
        _count(json['votesAgainst']) ?? _count(json['no_votes']) ?? 0,
    // core4 has no abstain option.
    'votesAbstain': _count(json['votesAbstain']) ?? 0,
    'votingDeadlineBlock':
        _count(json['votingDeadlineBlock']) ?? _count(json['voting_deadline']),
    'finalizedAtBlock':
        _count(json['finalizedAtBlock']) ?? _count(json['finalized_at_block']),
  };
}

String? _nonEmptyString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

int? _count(Object? value) => value is num && value >= 0 ? value.toInt() : null;

/// `FailedQuorum` → `failed_quorum`; legacy lowercase values pass through.
String? _snakeEnum(Object? value) {
  final s = _nonEmptyString(value);
  if (s == null) return null;
  return s
      .replaceAllMapped(
        RegExp(r'(?<=[a-z0-9])([A-Z])'),
        (m) => '_${m.group(1)}',
      )
      .toLowerCase();
}

String? _statusOf(Object? value) => _snakeEnum(value);

/// core4's `update` is an externally tagged serde enum: `{"EmissionRate": 5}`,
/// `{"StakeRequired": {...}}`, or a bare variant name. States the on-chain
/// change as data; never invents prose.
String? _describeUpdate(Object? update) {
  if (update is String && update.isNotEmpty) {
    return 'On-chain parameter update: $update';
  }
  if (update is Map && update.length == 1) {
    final entry = update.entries.single;
    return 'On-chain parameter update: ${entry.key} = ${entry.value}';
  }
  return null;
}
