// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sensor_reading_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SensorReadingModel {

 int? get id; double get latitude; double get longitude; double get pressureHpa; DateTime get timestamp; bool get synced;
/// Create a copy of SensorReadingModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SensorReadingModelCopyWith<SensorReadingModel> get copyWith => _$SensorReadingModelCopyWithImpl<SensorReadingModel>(this as SensorReadingModel, _$identity);

  /// Serializes this SensorReadingModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SensorReadingModel&&(identical(other.id, id) || other.id == id)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.pressureHpa, pressureHpa) || other.pressureHpa == pressureHpa)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.synced, synced) || other.synced == synced));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,latitude,longitude,pressureHpa,timestamp,synced);

@override
String toString() {
  return 'SensorReadingModel(id: $id, latitude: $latitude, longitude: $longitude, pressureHpa: $pressureHpa, timestamp: $timestamp, synced: $synced)';
}


}

/// @nodoc
abstract mixin class $SensorReadingModelCopyWith<$Res>  {
  factory $SensorReadingModelCopyWith(SensorReadingModel value, $Res Function(SensorReadingModel) _then) = _$SensorReadingModelCopyWithImpl;
@useResult
$Res call({
 int? id, double latitude, double longitude, double pressureHpa, DateTime timestamp, bool synced
});




}
/// @nodoc
class _$SensorReadingModelCopyWithImpl<$Res>
    implements $SensorReadingModelCopyWith<$Res> {
  _$SensorReadingModelCopyWithImpl(this._self, this._then);

  final SensorReadingModel _self;
  final $Res Function(SensorReadingModel) _then;

/// Create a copy of SensorReadingModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? latitude = null,Object? longitude = null,Object? pressureHpa = null,Object? timestamp = null,Object? synced = null,}) {
  return _then(SensorReadingModel(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,pressureHpa: null == pressureHpa ? _self.pressureHpa : pressureHpa // ignore: cast_nullable_to_non_nullable
as double,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,synced: null == synced ? _self.synced : synced // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SensorReadingModel].
extension SensorReadingModelPatterns on SensorReadingModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SensorReadingModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SensorReadingModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SensorReadingModel value)  $default,){
final _that = this;
switch (_that) {
case _SensorReadingModel():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SensorReadingModel value)?  $default,){
final _that = this;
switch (_that) {
case _SensorReadingModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  double latitude,  double longitude,  double pressureHpa,  DateTime timestamp,  bool synced)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SensorReadingModel() when $default != null:
return $default(_that.id,_that.latitude,_that.longitude,_that.pressureHpa,_that.timestamp,_that.synced);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  double latitude,  double longitude,  double pressureHpa,  DateTime timestamp,  bool synced)  $default,) {final _that = this;
switch (_that) {
case _SensorReadingModel():
return $default(_that.id,_that.latitude,_that.longitude,_that.pressureHpa,_that.timestamp,_that.synced);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  double latitude,  double longitude,  double pressureHpa,  DateTime timestamp,  bool synced)?  $default,) {final _that = this;
switch (_that) {
case _SensorReadingModel() when $default != null:
return $default(_that.id,_that.latitude,_that.longitude,_that.pressureHpa,_that.timestamp,_that.synced);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SensorReadingModel implements SensorReadingModel {
  const _SensorReadingModel({this.id, required this.latitude, required this.longitude, required this.pressureHpa, required this.timestamp, this.synced = false});
  factory _SensorReadingModel.fromJson(Map<String, dynamic> json) => _$SensorReadingModelFromJson(json);

@override final  int? id;
@override final  double latitude;
@override final  double longitude;
@override final  double pressureHpa;
@override final  DateTime timestamp;
@override@JsonKey() final  bool synced;

/// Create a copy of SensorReadingModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SensorReadingModelCopyWith<_SensorReadingModel> get copyWith => __$SensorReadingModelCopyWithImpl<_SensorReadingModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SensorReadingModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SensorReadingModel&&(identical(other.id, id) || other.id == id)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.pressureHpa, pressureHpa) || other.pressureHpa == pressureHpa)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.synced, synced) || other.synced == synced));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,latitude,longitude,pressureHpa,timestamp,synced);

@override
String toString() {
  return 'SensorReadingModel(id: $id, latitude: $latitude, longitude: $longitude, pressureHpa: $pressureHpa, timestamp: $timestamp, synced: $synced)';
}


}

/// @nodoc
abstract mixin class _$SensorReadingModelCopyWith<$Res> implements $SensorReadingModelCopyWith<$Res> {
  factory _$SensorReadingModelCopyWith(_SensorReadingModel value, $Res Function(_SensorReadingModel) _then) = __$SensorReadingModelCopyWithImpl;
@override @useResult
$Res call({
 int? id, double latitude, double longitude, double pressureHpa, DateTime timestamp, bool synced
});




}
/// @nodoc
class __$SensorReadingModelCopyWithImpl<$Res>
    implements _$SensorReadingModelCopyWith<$Res> {
  __$SensorReadingModelCopyWithImpl(this._self, this._then);

  final _SensorReadingModel _self;
  final $Res Function(_SensorReadingModel) _then;

/// Create a copy of SensorReadingModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? latitude = null,Object? longitude = null,Object? pressureHpa = null,Object? timestamp = null,Object? synced = null,}) {
  return _then(_SensorReadingModel(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,pressureHpa: null == pressureHpa ? _self.pressureHpa : pressureHpa // ignore: cast_nullable_to_non_nullable
as double,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,synced: null == synced ? _self.synced : synced // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
