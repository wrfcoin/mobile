// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'alert_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AlertModel {

 String get id; String get type; String get severity; String get location; String get timestamp; String get description;
/// Create a copy of AlertModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlertModelCopyWith<AlertModel> get copyWith => _$AlertModelCopyWithImpl<AlertModel>(this as AlertModel, _$identity);

  /// Serializes this AlertModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlertModel&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.location, location) || other.location == location)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.description, description) || other.description == description));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,type,severity,location,timestamp,description);

@override
String toString() {
  return 'AlertModel(id: $id, type: $type, severity: $severity, location: $location, timestamp: $timestamp, description: $description)';
}


}

/// @nodoc
abstract mixin class $AlertModelCopyWith<$Res>  {
  factory $AlertModelCopyWith(AlertModel value, $Res Function(AlertModel) _then) = _$AlertModelCopyWithImpl;
@useResult
$Res call({
 String id, String type, String severity, String location, String timestamp, String description
});




}
/// @nodoc
class _$AlertModelCopyWithImpl<$Res>
    implements $AlertModelCopyWith<$Res> {
  _$AlertModelCopyWithImpl(this._self, this._then);

  final AlertModel _self;
  final $Res Function(AlertModel) _then;

/// Create a copy of AlertModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? severity = null,Object? location = null,Object? timestamp = null,Object? description = null,}) {
  return _then(AlertModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as String,location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AlertModel].
extension AlertModelPatterns on AlertModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AlertModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AlertModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AlertModel value)  $default,){
final _that = this;
switch (_that) {
case _AlertModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AlertModel value)?  $default,){
final _that = this;
switch (_that) {
case _AlertModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String type,  String severity,  String location,  String timestamp,  String description)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AlertModel() when $default != null:
return $default(_that.id,_that.type,_that.severity,_that.location,_that.timestamp,_that.description);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String type,  String severity,  String location,  String timestamp,  String description)  $default,) {final _that = this;
switch (_that) {
case _AlertModel():
return $default(_that.id,_that.type,_that.severity,_that.location,_that.timestamp,_that.description);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String type,  String severity,  String location,  String timestamp,  String description)?  $default,) {final _that = this;
switch (_that) {
case _AlertModel() when $default != null:
return $default(_that.id,_that.type,_that.severity,_that.location,_that.timestamp,_that.description);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AlertModel implements AlertModel {
  const _AlertModel({required this.id, required this.type, required this.severity, required this.location, required this.timestamp, required this.description});
  factory _AlertModel.fromJson(Map<String, dynamic> json) => _$AlertModelFromJson(json);

@override final  String id;
@override final  String type;
@override final  String severity;
@override final  String location;
@override final  String timestamp;
@override final  String description;

/// Create a copy of AlertModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlertModelCopyWith<_AlertModel> get copyWith => __$AlertModelCopyWithImpl<_AlertModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AlertModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AlertModel&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.location, location) || other.location == location)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.description, description) || other.description == description));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,type,severity,location,timestamp,description);

@override
String toString() {
  return 'AlertModel(id: $id, type: $type, severity: $severity, location: $location, timestamp: $timestamp, description: $description)';
}


}

/// @nodoc
abstract mixin class _$AlertModelCopyWith<$Res> implements $AlertModelCopyWith<$Res> {
  factory _$AlertModelCopyWith(_AlertModel value, $Res Function(_AlertModel) _then) = __$AlertModelCopyWithImpl;
@override @useResult
$Res call({
 String id, String type, String severity, String location, String timestamp, String description
});




}
/// @nodoc
class __$AlertModelCopyWithImpl<$Res>
    implements _$AlertModelCopyWith<$Res> {
  __$AlertModelCopyWithImpl(this._self, this._then);

  final _AlertModel _self;
  final $Res Function(_AlertModel) _then;

/// Create a copy of AlertModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? severity = null,Object? location = null,Object? timestamp = null,Object? description = null,}) {
  return _then(_AlertModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as String,location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
