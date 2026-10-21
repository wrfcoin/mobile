// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'proposal_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ProposalModel {

 String get id; String get title; String get description; String get proposalType; String get status; String? get votingPeriod; String? get createdAt; int get votesFor; int get votesAgainst; int get votesAbstain; int? get votingDeadlineBlock; int? get finalizedAtBlock;
/// Create a copy of ProposalModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProposalModelCopyWith<ProposalModel> get copyWith => _$ProposalModelCopyWithImpl<ProposalModel>(this as ProposalModel, _$identity);

  /// Serializes this ProposalModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProposalModel&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.proposalType, proposalType) || other.proposalType == proposalType)&&(identical(other.status, status) || other.status == status)&&(identical(other.votingPeriod, votingPeriod) || other.votingPeriod == votingPeriod)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.votesFor, votesFor) || other.votesFor == votesFor)&&(identical(other.votesAgainst, votesAgainst) || other.votesAgainst == votesAgainst)&&(identical(other.votesAbstain, votesAbstain) || other.votesAbstain == votesAbstain)&&(identical(other.votingDeadlineBlock, votingDeadlineBlock) || other.votingDeadlineBlock == votingDeadlineBlock)&&(identical(other.finalizedAtBlock, finalizedAtBlock) || other.finalizedAtBlock == finalizedAtBlock));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,description,proposalType,status,votingPeriod,createdAt,votesFor,votesAgainst,votesAbstain,votingDeadlineBlock,finalizedAtBlock);

@override
String toString() {
  return 'ProposalModel(id: $id, title: $title, description: $description, proposalType: $proposalType, status: $status, votingPeriod: $votingPeriod, createdAt: $createdAt, votesFor: $votesFor, votesAgainst: $votesAgainst, votesAbstain: $votesAbstain, votingDeadlineBlock: $votingDeadlineBlock, finalizedAtBlock: $finalizedAtBlock)';
}


}

/// @nodoc
abstract mixin class $ProposalModelCopyWith<$Res>  {
  factory $ProposalModelCopyWith(ProposalModel value, $Res Function(ProposalModel) _then) = _$ProposalModelCopyWithImpl;
@useResult
$Res call({
 String id, String title, String description, String proposalType, String status, String? votingPeriod, String? createdAt, int votesFor, int votesAgainst, int votesAbstain, int? votingDeadlineBlock, int? finalizedAtBlock
});




}
/// @nodoc
class _$ProposalModelCopyWithImpl<$Res>
    implements $ProposalModelCopyWith<$Res> {
  _$ProposalModelCopyWithImpl(this._self, this._then);

  final ProposalModel _self;
  final $Res Function(ProposalModel) _then;

/// Create a copy of ProposalModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? description = null,Object? proposalType = null,Object? status = null,Object? votingPeriod = freezed,Object? createdAt = freezed,Object? votesFor = null,Object? votesAgainst = null,Object? votesAbstain = null,Object? votingDeadlineBlock = freezed,Object? finalizedAtBlock = freezed,}) {
  return _then(ProposalModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,proposalType: null == proposalType ? _self.proposalType : proposalType // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,votingPeriod: freezed == votingPeriod ? _self.votingPeriod : votingPeriod // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,votesFor: null == votesFor ? _self.votesFor : votesFor // ignore: cast_nullable_to_non_nullable
as int,votesAgainst: null == votesAgainst ? _self.votesAgainst : votesAgainst // ignore: cast_nullable_to_non_nullable
as int,votesAbstain: null == votesAbstain ? _self.votesAbstain : votesAbstain // ignore: cast_nullable_to_non_nullable
as int,votingDeadlineBlock: freezed == votingDeadlineBlock ? _self.votingDeadlineBlock : votingDeadlineBlock // ignore: cast_nullable_to_non_nullable
as int?,finalizedAtBlock: freezed == finalizedAtBlock ? _self.finalizedAtBlock : finalizedAtBlock // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ProposalModel].
extension ProposalModelPatterns on ProposalModel {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProposalModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProposalModel() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProposalModel value)  $default,){
final _that = this;
switch (_that) {
case _ProposalModel():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProposalModel value)?  $default,){
final _that = this;
switch (_that) {
case _ProposalModel() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String description,  String proposalType,  String status,  String? votingPeriod,  String? createdAt,  int votesFor,  int votesAgainst,  int votesAbstain,  int? votingDeadlineBlock,  int? finalizedAtBlock)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProposalModel() when $default != null:
return $default(_that.id,_that.title,_that.description,_that.proposalType,_that.status,_that.votingPeriod,_that.createdAt,_that.votesFor,_that.votesAgainst,_that.votesAbstain,_that.votingDeadlineBlock,_that.finalizedAtBlock);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String description,  String proposalType,  String status,  String? votingPeriod,  String? createdAt,  int votesFor,  int votesAgainst,  int votesAbstain,  int? votingDeadlineBlock,  int? finalizedAtBlock)  $default,) {final _that = this;
switch (_that) {
case _ProposalModel():
return $default(_that.id,_that.title,_that.description,_that.proposalType,_that.status,_that.votingPeriod,_that.createdAt,_that.votesFor,_that.votesAgainst,_that.votesAbstain,_that.votingDeadlineBlock,_that.finalizedAtBlock);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String description,  String proposalType,  String status,  String? votingPeriod,  String? createdAt,  int votesFor,  int votesAgainst,  int votesAbstain,  int? votingDeadlineBlock,  int? finalizedAtBlock)?  $default,) {final _that = this;
switch (_that) {
case _ProposalModel() when $default != null:
return $default(_that.id,_that.title,_that.description,_that.proposalType,_that.status,_that.votingPeriod,_that.createdAt,_that.votesFor,_that.votesAgainst,_that.votesAbstain,_that.votingDeadlineBlock,_that.finalizedAtBlock);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProposalModel implements ProposalModel {
  const _ProposalModel({required this.id, required this.title, required this.description, this.proposalType = 'standard', this.status = 'active', this.votingPeriod, this.createdAt, this.votesFor = 0, this.votesAgainst = 0, this.votesAbstain = 0, this.votingDeadlineBlock, this.finalizedAtBlock});
  factory _ProposalModel.fromJson(Map<String, dynamic> json) => _$ProposalModelFromJson(json);

@override final  String id;
@override final  String title;
@override final  String description;
@override@JsonKey() final  String proposalType;
@override@JsonKey() final  String status;
@override final  String? votingPeriod;
@override final  String? createdAt;
@override@JsonKey() final  int votesFor;
@override@JsonKey() final  int votesAgainst;
@override@JsonKey() final  int votesAbstain;
@override final  int? votingDeadlineBlock;
@override final  int? finalizedAtBlock;

/// Create a copy of ProposalModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProposalModelCopyWith<_ProposalModel> get copyWith => __$ProposalModelCopyWithImpl<_ProposalModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProposalModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProposalModel&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.proposalType, proposalType) || other.proposalType == proposalType)&&(identical(other.status, status) || other.status == status)&&(identical(other.votingPeriod, votingPeriod) || other.votingPeriod == votingPeriod)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.votesFor, votesFor) || other.votesFor == votesFor)&&(identical(other.votesAgainst, votesAgainst) || other.votesAgainst == votesAgainst)&&(identical(other.votesAbstain, votesAbstain) || other.votesAbstain == votesAbstain)&&(identical(other.votingDeadlineBlock, votingDeadlineBlock) || other.votingDeadlineBlock == votingDeadlineBlock)&&(identical(other.finalizedAtBlock, finalizedAtBlock) || other.finalizedAtBlock == finalizedAtBlock));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,description,proposalType,status,votingPeriod,createdAt,votesFor,votesAgainst,votesAbstain,votingDeadlineBlock,finalizedAtBlock);

@override
String toString() {
  return 'ProposalModel(id: $id, title: $title, description: $description, proposalType: $proposalType, status: $status, votingPeriod: $votingPeriod, createdAt: $createdAt, votesFor: $votesFor, votesAgainst: $votesAgainst, votesAbstain: $votesAbstain, votingDeadlineBlock: $votingDeadlineBlock, finalizedAtBlock: $finalizedAtBlock)';
}


}

/// @nodoc
abstract mixin class _$ProposalModelCopyWith<$Res> implements $ProposalModelCopyWith<$Res> {
  factory _$ProposalModelCopyWith(_ProposalModel value, $Res Function(_ProposalModel) _then) = __$ProposalModelCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String description, String proposalType, String status, String? votingPeriod, String? createdAt, int votesFor, int votesAgainst, int votesAbstain, int? votingDeadlineBlock, int? finalizedAtBlock
});




}
/// @nodoc
class __$ProposalModelCopyWithImpl<$Res>
    implements _$ProposalModelCopyWith<$Res> {
  __$ProposalModelCopyWithImpl(this._self, this._then);

  final _ProposalModel _self;
  final $Res Function(_ProposalModel) _then;

/// Create a copy of ProposalModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? description = null,Object? proposalType = null,Object? status = null,Object? votingPeriod = freezed,Object? createdAt = freezed,Object? votesFor = null,Object? votesAgainst = null,Object? votesAbstain = null,Object? votingDeadlineBlock = freezed,Object? finalizedAtBlock = freezed,}) {
  return _then(_ProposalModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,proposalType: null == proposalType ? _self.proposalType : proposalType // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,votingPeriod: freezed == votingPeriod ? _self.votingPeriod : votingPeriod // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,votesFor: null == votesFor ? _self.votesFor : votesFor // ignore: cast_nullable_to_non_nullable
as int,votesAgainst: null == votesAgainst ? _self.votesAgainst : votesAgainst // ignore: cast_nullable_to_non_nullable
as int,votesAbstain: null == votesAbstain ? _self.votesAbstain : votesAbstain // ignore: cast_nullable_to_non_nullable
as int,votingDeadlineBlock: freezed == votingDeadlineBlock ? _self.votingDeadlineBlock : votingDeadlineBlock // ignore: cast_nullable_to_non_nullable
as int?,finalizedAtBlock: freezed == finalizedAtBlock ? _self.finalizedAtBlock : finalizedAtBlock // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
