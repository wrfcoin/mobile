// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transaction_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TransactionModel {

 String get hash; String? get eventId; String? get settlement; int get blockNumber;/// Null when the backend did not report a time (the B3 core4 history
/// window carries none).
 String? get timestamp; String get from;/// Null when the backend did not report a recipient.
 String? get to;/// Null when the backend did not report an amount. Never defaulted.
 String? get value; String get fee; String get memo;/// Null when the backend did not report a status. Never defaulted.
 String? get status; String get type;/// 'incoming', 'outgoing', 'self' or 'unknown'. Never assumed.
 String get direction;
/// Create a copy of TransactionModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransactionModelCopyWith<TransactionModel> get copyWith => _$TransactionModelCopyWithImpl<TransactionModel>(this as TransactionModel, _$identity);

  /// Serializes this TransactionModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TransactionModel;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TransactionModel&&(identical(other.hash, _this.hash) || other.hash == _this.hash)&&(identical(other.eventId, _this.eventId) || other.eventId == _this.eventId)&&(identical(other.settlement, _this.settlement) || other.settlement == _this.settlement)&&(identical(other.blockNumber, _this.blockNumber) || other.blockNumber == _this.blockNumber)&&(identical(other.timestamp, _this.timestamp) || other.timestamp == _this.timestamp)&&(identical(other.from, _this.from) || other.from == _this.from)&&(identical(other.to, _this.to) || other.to == _this.to)&&(identical(other.value, _this.value) || other.value == _this.value)&&(identical(other.fee, _this.fee) || other.fee == _this.fee)&&(identical(other.memo, _this.memo) || other.memo == _this.memo)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.direction, _this.direction) || other.direction == _this.direction));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TransactionModel;
  return Object.hash(runtimeType,_this.hash,_this.eventId,_this.settlement,_this.blockNumber,_this.timestamp,_this.from,_this.to,_this.value,_this.fee,_this.memo,_this.status,_this.type,_this.direction);
}

@override
String toString() {
  final _this = this as TransactionModel;
  return 'TransactionModel(hash: ${_this.hash}, eventId: ${_this.eventId}, settlement: ${_this.settlement}, blockNumber: ${_this.blockNumber}, timestamp: ${_this.timestamp}, from: ${_this.from}, to: ${_this.to}, value: ${_this.value}, fee: ${_this.fee}, memo: ${_this.memo}, status: ${_this.status}, type: ${_this.type}, direction: ${_this.direction})';
}


}

/// @nodoc
abstract mixin class $TransactionModelCopyWith<$Res>  {
  factory $TransactionModelCopyWith(TransactionModel value, $Res Function(TransactionModel) _then) = _$TransactionModelCopyWithImpl;
@useResult
$Res call({
 String hash, String? eventId, String? settlement, int blockNumber, String? timestamp, String from, String? to, String? value, String fee, String memo, String? status, String type, String direction
});




}
/// @nodoc
class _$TransactionModelCopyWithImpl<$Res>
    implements $TransactionModelCopyWith<$Res> {
  _$TransactionModelCopyWithImpl(this._self, this._then);

  final TransactionModel _self;
  final $Res Function(TransactionModel) _then;

/// Create a copy of TransactionModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? hash = null,Object? eventId = freezed,Object? settlement = freezed,Object? blockNumber = null,Object? timestamp = freezed,Object? from = null,Object? to = freezed,Object? value = freezed,Object? fee = null,Object? memo = null,Object? status = freezed,Object? type = null,Object? direction = null,}) {
  return _then(TransactionModel(
hash: null == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String,eventId: freezed == eventId ? _self.eventId : eventId // ignore: cast_nullable_to_non_nullable
as String?,settlement: freezed == settlement ? _self.settlement : settlement // ignore: cast_nullable_to_non_nullable
as String?,blockNumber: null == blockNumber ? _self.blockNumber : blockNumber // ignore: cast_nullable_to_non_nullable
as int,timestamp: freezed == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String?,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,to: freezed == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String?,fee: null == fee ? _self.fee : fee // ignore: cast_nullable_to_non_nullable
as String,memo: null == memo ? _self.memo : memo // ignore: cast_nullable_to_non_nullable
as String,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TransactionModel].
extension TransactionModelPatterns on TransactionModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TransactionModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TransactionModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TransactionModel value)  $default,){
final _that = this;
switch (_that) {
case _TransactionModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TransactionModel value)?  $default,){
final _that = this;
switch (_that) {
case _TransactionModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String hash,  String? eventId,  String? settlement,  int blockNumber,  String? timestamp,  String from,  String? to,  String? value,  String fee,  String memo,  String? status,  String type,  String direction)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TransactionModel() when $default != null:
return $default(_that.hash,_that.eventId,_that.settlement,_that.blockNumber,_that.timestamp,_that.from,_that.to,_that.value,_that.fee,_that.memo,_that.status,_that.type,_that.direction);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String hash,  String? eventId,  String? settlement,  int blockNumber,  String? timestamp,  String from,  String? to,  String? value,  String fee,  String memo,  String? status,  String type,  String direction)  $default,) {final _that = this;
switch (_that) {
case _TransactionModel():
return $default(_that.hash,_that.eventId,_that.settlement,_that.blockNumber,_that.timestamp,_that.from,_that.to,_that.value,_that.fee,_that.memo,_that.status,_that.type,_that.direction);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String hash,  String? eventId,  String? settlement,  int blockNumber,  String? timestamp,  String from,  String? to,  String? value,  String fee,  String memo,  String? status,  String type,  String direction)?  $default,) {final _that = this;
switch (_that) {
case _TransactionModel() when $default != null:
return $default(_that.hash,_that.eventId,_that.settlement,_that.blockNumber,_that.timestamp,_that.from,_that.to,_that.value,_that.fee,_that.memo,_that.status,_that.type,_that.direction);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TransactionModel implements TransactionModel {
  const _TransactionModel({required this.hash, this.eventId, this.settlement, this.blockNumber = 0, this.timestamp, required this.from, this.to, this.value, this.fee = '0', this.memo = '', this.status, this.type = 'transfer', this.direction = 'unknown'});
  factory _TransactionModel.fromJson(Map<String, dynamic> json) => _$TransactionModelFromJson(json);

@override final  String hash;
@override final  String? eventId;
@override final  String? settlement;
@override@JsonKey() final  int blockNumber;
/// Null when the backend did not report a time (the B3 core4 history
/// window carries none).
@override final  String? timestamp;
@override final  String from;
/// Null when the backend did not report a recipient.
@override final  String? to;
/// Null when the backend did not report an amount. Never defaulted.
@override final  String? value;
@override@JsonKey() final  String fee;
@override@JsonKey() final  String memo;
/// Null when the backend did not report a status. Never defaulted.
@override final  String? status;
@override@JsonKey() final  String type;
/// 'incoming', 'outgoing', 'self' or 'unknown'. Never assumed.
@override@JsonKey() final  String direction;

/// Create a copy of TransactionModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TransactionModelCopyWith<_TransactionModel> get copyWith => __$TransactionModelCopyWithImpl<_TransactionModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TransactionModelToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TransactionModel&&(identical(other.hash, hash) || other.hash == hash)&&(identical(other.eventId, eventId) || other.eventId == eventId)&&(identical(other.settlement, settlement) || other.settlement == settlement)&&(identical(other.blockNumber, blockNumber) || other.blockNumber == blockNumber)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to)&&(identical(other.value, value) || other.value == value)&&(identical(other.fee, fee) || other.fee == fee)&&(identical(other.memo, memo) || other.memo == memo)&&(identical(other.status, status) || other.status == status)&&(identical(other.type, type) || other.type == type)&&(identical(other.direction, direction) || other.direction == direction));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,hash,eventId,settlement,blockNumber,timestamp,from,to,value,fee,memo,status,type,direction);
}

@override
String toString() {
    return 'TransactionModel(hash: $hash, eventId: $eventId, settlement: $settlement, blockNumber: $blockNumber, timestamp: $timestamp, from: $from, to: $to, value: $value, fee: $fee, memo: $memo, status: $status, type: $type, direction: $direction)';
}


}

/// @nodoc
abstract mixin class _$TransactionModelCopyWith<$Res> implements $TransactionModelCopyWith<$Res> {
  factory _$TransactionModelCopyWith(_TransactionModel value, $Res Function(_TransactionModel) _then) = __$TransactionModelCopyWithImpl;
@override @useResult
$Res call({
 String hash, String? eventId, String? settlement, int blockNumber, String? timestamp, String from, String? to, String? value, String fee, String memo, String? status, String type, String direction
});




}
/// @nodoc
class __$TransactionModelCopyWithImpl<$Res>
    implements _$TransactionModelCopyWith<$Res> {
  __$TransactionModelCopyWithImpl(this._self, this._then);

  final _TransactionModel _self;
  final $Res Function(_TransactionModel) _then;

/// Create a copy of TransactionModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hash = null,Object? eventId = freezed,Object? settlement = freezed,Object? blockNumber = null,Object? timestamp = freezed,Object? from = null,Object? to = freezed,Object? value = freezed,Object? fee = null,Object? memo = null,Object? status = freezed,Object? type = null,Object? direction = null,}) {
  return _then(_TransactionModel(
hash: null == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String,eventId: freezed == eventId ? _self.eventId : eventId // ignore: cast_nullable_to_non_nullable
as String?,settlement: freezed == settlement ? _self.settlement : settlement // ignore: cast_nullable_to_non_nullable
as String?,blockNumber: null == blockNumber ? _self.blockNumber : blockNumber // ignore: cast_nullable_to_non_nullable
as int,timestamp: freezed == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String?,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,to: freezed == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String?,fee: null == fee ? _self.fee : fee // ignore: cast_nullable_to_non_nullable
as String,memo: null == memo ? _self.memo : memo // ignore: cast_nullable_to_non_nullable
as String,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
