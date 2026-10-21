import 'package:freezed_annotation/freezed_annotation.dart';

import 'proposal_json.dart';

part 'proposal_model.freezed.dart';
part 'proposal_model.g.dart';

@Freezed()
sealed class ProposalModel with _$ProposalModel {
  const factory ProposalModel({
    required String id,
    required String title,
    required String description,
    @Default('standard') String proposalType,
    @Default('active') String status,
    String? votingPeriod,
    String? createdAt,
    @Default(0) int votesFor,
    @Default(0) int votesAgainst,
    @Default(0) int votesAbstain,
    // core4 block heights (no wall-clock timestamps exist on chain).
    int? votingDeadlineBlock,
    int? finalizedAtBlock,
  }) = _ProposalModel;

  /// Tolerant reader for backend payloads, including core4's native records.
  /// Throws [FormatException] for an item with no usable id.
  factory ProposalModel.fromApiJson(Object? raw) =>
      ProposalModel.fromJson(normalizeProposalJson(raw));

  factory ProposalModel.fromJson(Map<String, dynamic> json) =>
      _$ProposalModelFromJson(json);
}
