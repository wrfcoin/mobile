// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'proposal_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ProposalModel _$ProposalModelFromJson(Map<String, dynamic> json) =>
    _ProposalModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      proposalType: json['proposalType'] as String? ?? 'standard',
      status: json['status'] as String? ?? 'active',
      votingPeriod: json['votingPeriod'] as String?,
      createdAt: json['createdAt'] as String?,
      votesFor: (json['votesFor'] as num?)?.toInt() ?? 0,
      votesAgainst: (json['votesAgainst'] as num?)?.toInt() ?? 0,
      votesAbstain: (json['votesAbstain'] as num?)?.toInt() ?? 0,
      votingDeadlineBlock: (json['votingDeadlineBlock'] as num?)?.toInt(),
      finalizedAtBlock: (json['finalizedAtBlock'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ProposalModelToJson(_ProposalModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'proposalType': instance.proposalType,
      'status': instance.status,
      'votingPeriod': instance.votingPeriod,
      'createdAt': instance.createdAt,
      'votesFor': instance.votesFor,
      'votesAgainst': instance.votesAgainst,
      'votesAbstain': instance.votesAbstain,
      'votingDeadlineBlock': instance.votingDeadlineBlock,
      'finalizedAtBlock': instance.finalizedAtBlock,
    };
