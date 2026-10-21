// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'wrf_forecast_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WrfForecastPoint {

/// ISO-8601 timestamp for this forecast slot.
 String get timestamp;/// Mean air temperature in degrees Celsius.
 double get temperatureC;/// Maximum temperature for this slot (°C).
 double get temperatureMaxC;/// Minimum temperature for this slot (°C).
 double get temperatureMinC;/// Total precipitation in millimetres.
 double get precipitationMm;/// Wind speed in metres per second.
 double get windSpeedMs;/// Model confidence score between 0.0 (low) and 1.0 (high).
 double get forecastConfidence;/// Heating degree days relative to base temperature 18.3°C.
 double get hdd;/// Cooling degree days relative to base temperature 18.3°C.
 double get cdd;
/// Create a copy of WrfForecastPoint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WrfForecastPointCopyWith<WrfForecastPoint> get copyWith => _$WrfForecastPointCopyWithImpl<WrfForecastPoint>(this as WrfForecastPoint, _$identity);

  /// Serializes this WrfForecastPoint to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WrfForecastPoint&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.temperatureC, temperatureC) || other.temperatureC == temperatureC)&&(identical(other.temperatureMaxC, temperatureMaxC) || other.temperatureMaxC == temperatureMaxC)&&(identical(other.temperatureMinC, temperatureMinC) || other.temperatureMinC == temperatureMinC)&&(identical(other.precipitationMm, precipitationMm) || other.precipitationMm == precipitationMm)&&(identical(other.windSpeedMs, windSpeedMs) || other.windSpeedMs == windSpeedMs)&&(identical(other.forecastConfidence, forecastConfidence) || other.forecastConfidence == forecastConfidence)&&(identical(other.hdd, hdd) || other.hdd == hdd)&&(identical(other.cdd, cdd) || other.cdd == cdd));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,timestamp,temperatureC,temperatureMaxC,temperatureMinC,precipitationMm,windSpeedMs,forecastConfidence,hdd,cdd);

@override
String toString() {
  return 'WrfForecastPoint(timestamp: $timestamp, temperatureC: $temperatureC, temperatureMaxC: $temperatureMaxC, temperatureMinC: $temperatureMinC, precipitationMm: $precipitationMm, windSpeedMs: $windSpeedMs, forecastConfidence: $forecastConfidence, hdd: $hdd, cdd: $cdd)';
}


}

/// @nodoc
abstract mixin class $WrfForecastPointCopyWith<$Res>  {
  factory $WrfForecastPointCopyWith(WrfForecastPoint value, $Res Function(WrfForecastPoint) _then) = _$WrfForecastPointCopyWithImpl;
@useResult
$Res call({
 String timestamp, double temperatureC, double temperatureMaxC, double temperatureMinC, double precipitationMm, double windSpeedMs, double forecastConfidence, double hdd, double cdd
});




}
/// @nodoc
class _$WrfForecastPointCopyWithImpl<$Res>
    implements $WrfForecastPointCopyWith<$Res> {
  _$WrfForecastPointCopyWithImpl(this._self, this._then);

  final WrfForecastPoint _self;
  final $Res Function(WrfForecastPoint) _then;

/// Create a copy of WrfForecastPoint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? timestamp = null,Object? temperatureC = null,Object? temperatureMaxC = null,Object? temperatureMinC = null,Object? precipitationMm = null,Object? windSpeedMs = null,Object? forecastConfidence = null,Object? hdd = null,Object? cdd = null,}) {
  return _then(WrfForecastPoint(
timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String,temperatureC: null == temperatureC ? _self.temperatureC : temperatureC // ignore: cast_nullable_to_non_nullable
as double,temperatureMaxC: null == temperatureMaxC ? _self.temperatureMaxC : temperatureMaxC // ignore: cast_nullable_to_non_nullable
as double,temperatureMinC: null == temperatureMinC ? _self.temperatureMinC : temperatureMinC // ignore: cast_nullable_to_non_nullable
as double,precipitationMm: null == precipitationMm ? _self.precipitationMm : precipitationMm // ignore: cast_nullable_to_non_nullable
as double,windSpeedMs: null == windSpeedMs ? _self.windSpeedMs : windSpeedMs // ignore: cast_nullable_to_non_nullable
as double,forecastConfidence: null == forecastConfidence ? _self.forecastConfidence : forecastConfidence // ignore: cast_nullable_to_non_nullable
as double,hdd: null == hdd ? _self.hdd : hdd // ignore: cast_nullable_to_non_nullable
as double,cdd: null == cdd ? _self.cdd : cdd // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [WrfForecastPoint].
extension WrfForecastPointPatterns on WrfForecastPoint {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WrfForecastPoint value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WrfForecastPoint() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WrfForecastPoint value)  $default,){
final _that = this;
switch (_that) {
case _WrfForecastPoint():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WrfForecastPoint value)?  $default,){
final _that = this;
switch (_that) {
case _WrfForecastPoint() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String timestamp,  double temperatureC,  double temperatureMaxC,  double temperatureMinC,  double precipitationMm,  double windSpeedMs,  double forecastConfidence,  double hdd,  double cdd)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WrfForecastPoint() when $default != null:
return $default(_that.timestamp,_that.temperatureC,_that.temperatureMaxC,_that.temperatureMinC,_that.precipitationMm,_that.windSpeedMs,_that.forecastConfidence,_that.hdd,_that.cdd);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String timestamp,  double temperatureC,  double temperatureMaxC,  double temperatureMinC,  double precipitationMm,  double windSpeedMs,  double forecastConfidence,  double hdd,  double cdd)  $default,) {final _that = this;
switch (_that) {
case _WrfForecastPoint():
return $default(_that.timestamp,_that.temperatureC,_that.temperatureMaxC,_that.temperatureMinC,_that.precipitationMm,_that.windSpeedMs,_that.forecastConfidence,_that.hdd,_that.cdd);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String timestamp,  double temperatureC,  double temperatureMaxC,  double temperatureMinC,  double precipitationMm,  double windSpeedMs,  double forecastConfidence,  double hdd,  double cdd)?  $default,) {final _that = this;
switch (_that) {
case _WrfForecastPoint() when $default != null:
return $default(_that.timestamp,_that.temperatureC,_that.temperatureMaxC,_that.temperatureMinC,_that.precipitationMm,_that.windSpeedMs,_that.forecastConfidence,_that.hdd,_that.cdd);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WrfForecastPoint implements WrfForecastPoint {
  const _WrfForecastPoint({required this.timestamp, required this.temperatureC, required this.temperatureMaxC, required this.temperatureMinC, required this.precipitationMm, required this.windSpeedMs, this.forecastConfidence = 1.0, this.hdd = 0.0, this.cdd = 0.0});
  factory _WrfForecastPoint.fromJson(Map<String, dynamic> json) => _$WrfForecastPointFromJson(json);

/// ISO-8601 timestamp for this forecast slot.
@override final  String timestamp;
/// Mean air temperature in degrees Celsius.
@override final  double temperatureC;
/// Maximum temperature for this slot (°C).
@override final  double temperatureMaxC;
/// Minimum temperature for this slot (°C).
@override final  double temperatureMinC;
/// Total precipitation in millimetres.
@override final  double precipitationMm;
/// Wind speed in metres per second.
@override final  double windSpeedMs;
/// Model confidence score between 0.0 (low) and 1.0 (high).
@override@JsonKey() final  double forecastConfidence;
/// Heating degree days relative to base temperature 18.3°C.
@override@JsonKey() final  double hdd;
/// Cooling degree days relative to base temperature 18.3°C.
@override@JsonKey() final  double cdd;

/// Create a copy of WrfForecastPoint
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WrfForecastPointCopyWith<_WrfForecastPoint> get copyWith => __$WrfForecastPointCopyWithImpl<_WrfForecastPoint>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WrfForecastPointToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WrfForecastPoint&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.temperatureC, temperatureC) || other.temperatureC == temperatureC)&&(identical(other.temperatureMaxC, temperatureMaxC) || other.temperatureMaxC == temperatureMaxC)&&(identical(other.temperatureMinC, temperatureMinC) || other.temperatureMinC == temperatureMinC)&&(identical(other.precipitationMm, precipitationMm) || other.precipitationMm == precipitationMm)&&(identical(other.windSpeedMs, windSpeedMs) || other.windSpeedMs == windSpeedMs)&&(identical(other.forecastConfidence, forecastConfidence) || other.forecastConfidence == forecastConfidence)&&(identical(other.hdd, hdd) || other.hdd == hdd)&&(identical(other.cdd, cdd) || other.cdd == cdd));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,timestamp,temperatureC,temperatureMaxC,temperatureMinC,precipitationMm,windSpeedMs,forecastConfidence,hdd,cdd);

@override
String toString() {
  return 'WrfForecastPoint(timestamp: $timestamp, temperatureC: $temperatureC, temperatureMaxC: $temperatureMaxC, temperatureMinC: $temperatureMinC, precipitationMm: $precipitationMm, windSpeedMs: $windSpeedMs, forecastConfidence: $forecastConfidence, hdd: $hdd, cdd: $cdd)';
}


}

/// @nodoc
abstract mixin class _$WrfForecastPointCopyWith<$Res> implements $WrfForecastPointCopyWith<$Res> {
  factory _$WrfForecastPointCopyWith(_WrfForecastPoint value, $Res Function(_WrfForecastPoint) _then) = __$WrfForecastPointCopyWithImpl;
@override @useResult
$Res call({
 String timestamp, double temperatureC, double temperatureMaxC, double temperatureMinC, double precipitationMm, double windSpeedMs, double forecastConfidence, double hdd, double cdd
});




}
/// @nodoc
class __$WrfForecastPointCopyWithImpl<$Res>
    implements _$WrfForecastPointCopyWith<$Res> {
  __$WrfForecastPointCopyWithImpl(this._self, this._then);

  final _WrfForecastPoint _self;
  final $Res Function(_WrfForecastPoint) _then;

/// Create a copy of WrfForecastPoint
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? timestamp = null,Object? temperatureC = null,Object? temperatureMaxC = null,Object? temperatureMinC = null,Object? precipitationMm = null,Object? windSpeedMs = null,Object? forecastConfidence = null,Object? hdd = null,Object? cdd = null,}) {
  return _then(_WrfForecastPoint(
timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String,temperatureC: null == temperatureC ? _self.temperatureC : temperatureC // ignore: cast_nullable_to_non_nullable
as double,temperatureMaxC: null == temperatureMaxC ? _self.temperatureMaxC : temperatureMaxC // ignore: cast_nullable_to_non_nullable
as double,temperatureMinC: null == temperatureMinC ? _self.temperatureMinC : temperatureMinC // ignore: cast_nullable_to_non_nullable
as double,precipitationMm: null == precipitationMm ? _self.precipitationMm : precipitationMm // ignore: cast_nullable_to_non_nullable
as double,windSpeedMs: null == windSpeedMs ? _self.windSpeedMs : windSpeedMs // ignore: cast_nullable_to_non_nullable
as double,forecastConfidence: null == forecastConfidence ? _self.forecastConfidence : forecastConfidence // ignore: cast_nullable_to_non_nullable
as double,hdd: null == hdd ? _self.hdd : hdd // ignore: cast_nullable_to_non_nullable
as double,cdd: null == cdd ? _self.cdd : cdd // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$WrfForecastModel {

/// Location identifier.
 String get location;/// ISO-8601 timestamp when the WRF model run was generated.
 String get generatedAt;/// IPFS content identifier of the WRF NetCDF/output file.
 String get ipfsCid;/// `false` when this contains real WRF model output; `true` for a
/// fallback stub injected when the backend pipeline is unavailable.
 bool get isSimulated;/// Hourly forecast points for the next 48 hours (or whatever the model
/// run covers).
 List<WrfForecastPoint> get hourly;
/// Create a copy of WrfForecastModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WrfForecastModelCopyWith<WrfForecastModel> get copyWith => _$WrfForecastModelCopyWithImpl<WrfForecastModel>(this as WrfForecastModel, _$identity);

  /// Serializes this WrfForecastModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WrfForecastModel&&(identical(other.location, location) || other.location == location)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt)&&(identical(other.ipfsCid, ipfsCid) || other.ipfsCid == ipfsCid)&&(identical(other.isSimulated, isSimulated) || other.isSimulated == isSimulated)&&const DeepCollectionEquality().equals(other.hourly, hourly));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,location,generatedAt,ipfsCid,isSimulated,const DeepCollectionEquality().hash(hourly));

@override
String toString() {
  return 'WrfForecastModel(location: $location, generatedAt: $generatedAt, ipfsCid: $ipfsCid, isSimulated: $isSimulated, hourly: $hourly)';
}


}

/// @nodoc
abstract mixin class $WrfForecastModelCopyWith<$Res>  {
  factory $WrfForecastModelCopyWith(WrfForecastModel value, $Res Function(WrfForecastModel) _then) = _$WrfForecastModelCopyWithImpl;
@useResult
$Res call({
 String location, String generatedAt, String ipfsCid, bool isSimulated, List<WrfForecastPoint> hourly
});




}
/// @nodoc
class _$WrfForecastModelCopyWithImpl<$Res>
    implements $WrfForecastModelCopyWith<$Res> {
  _$WrfForecastModelCopyWithImpl(this._self, this._then);

  final WrfForecastModel _self;
  final $Res Function(WrfForecastModel) _then;

/// Create a copy of WrfForecastModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? location = null,Object? generatedAt = null,Object? ipfsCid = null,Object? isSimulated = null,Object? hourly = null,}) {
  return _then(WrfForecastModel(
location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as String,generatedAt: null == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as String,ipfsCid: null == ipfsCid ? _self.ipfsCid : ipfsCid // ignore: cast_nullable_to_non_nullable
as String,isSimulated: null == isSimulated ? _self.isSimulated : isSimulated // ignore: cast_nullable_to_non_nullable
as bool,hourly: null == hourly ? _self.hourly : hourly // ignore: cast_nullable_to_non_nullable
as List<WrfForecastPoint>,
  ));
}

}


/// Adds pattern-matching-related methods to [WrfForecastModel].
extension WrfForecastModelPatterns on WrfForecastModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WrfForecastModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WrfForecastModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WrfForecastModel value)  $default,){
final _that = this;
switch (_that) {
case _WrfForecastModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WrfForecastModel value)?  $default,){
final _that = this;
switch (_that) {
case _WrfForecastModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String location,  String generatedAt,  String ipfsCid,  bool isSimulated,  List<WrfForecastPoint> hourly)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WrfForecastModel() when $default != null:
return $default(_that.location,_that.generatedAt,_that.ipfsCid,_that.isSimulated,_that.hourly);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String location,  String generatedAt,  String ipfsCid,  bool isSimulated,  List<WrfForecastPoint> hourly)  $default,) {final _that = this;
switch (_that) {
case _WrfForecastModel():
return $default(_that.location,_that.generatedAt,_that.ipfsCid,_that.isSimulated,_that.hourly);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String location,  String generatedAt,  String ipfsCid,  bool isSimulated,  List<WrfForecastPoint> hourly)?  $default,) {final _that = this;
switch (_that) {
case _WrfForecastModel() when $default != null:
return $default(_that.location,_that.generatedAt,_that.ipfsCid,_that.isSimulated,_that.hourly);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WrfForecastModel implements WrfForecastModel {
  const _WrfForecastModel({required this.location, required this.generatedAt, required this.ipfsCid, this.isSimulated = false,  List<WrfForecastPoint> hourly = const []}): _hourly = hourly;
  factory _WrfForecastModel.fromJson(Map<String, dynamic> json) => _$WrfForecastModelFromJson(json);

/// Location identifier.
@override final  String location;
/// ISO-8601 timestamp when the WRF model run was generated.
@override final  String generatedAt;
/// IPFS content identifier of the WRF NetCDF/output file.
@override final  String ipfsCid;
/// `false` when this contains real WRF model output; `true` for a
/// fallback stub injected when the backend pipeline is unavailable.
@override@JsonKey() final  bool isSimulated;
/// Hourly forecast points for the next 48 hours (or whatever the model
/// run covers).
 final  List<WrfForecastPoint> _hourly;
/// Hourly forecast points for the next 48 hours (or whatever the model
/// run covers).
@override@JsonKey() List<WrfForecastPoint> get hourly {
  if (_hourly is EqualUnmodifiableListView) return _hourly;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_hourly);
}


/// Create a copy of WrfForecastModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WrfForecastModelCopyWith<_WrfForecastModel> get copyWith => __$WrfForecastModelCopyWithImpl<_WrfForecastModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WrfForecastModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WrfForecastModel&&(identical(other.location, location) || other.location == location)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt)&&(identical(other.ipfsCid, ipfsCid) || other.ipfsCid == ipfsCid)&&(identical(other.isSimulated, isSimulated) || other.isSimulated == isSimulated)&&const DeepCollectionEquality().equals(other._hourly, _hourly));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,location,generatedAt,ipfsCid,isSimulated,const DeepCollectionEquality().hash(_hourly));

@override
String toString() {
  return 'WrfForecastModel(location: $location, generatedAt: $generatedAt, ipfsCid: $ipfsCid, isSimulated: $isSimulated, hourly: $hourly)';
}


}

/// @nodoc
abstract mixin class _$WrfForecastModelCopyWith<$Res> implements $WrfForecastModelCopyWith<$Res> {
  factory _$WrfForecastModelCopyWith(_WrfForecastModel value, $Res Function(_WrfForecastModel) _then) = __$WrfForecastModelCopyWithImpl;
@override @useResult
$Res call({
 String location, String generatedAt, String ipfsCid, bool isSimulated, List<WrfForecastPoint> hourly
});




}
/// @nodoc
class __$WrfForecastModelCopyWithImpl<$Res>
    implements _$WrfForecastModelCopyWith<$Res> {
  __$WrfForecastModelCopyWithImpl(this._self, this._then);

  final _WrfForecastModel _self;
  final $Res Function(_WrfForecastModel) _then;

/// Create a copy of WrfForecastModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? location = null,Object? generatedAt = null,Object? ipfsCid = null,Object? isSimulated = null,Object? hourly = null,}) {
  return _then(_WrfForecastModel(
location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as String,generatedAt: null == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as String,ipfsCid: null == ipfsCid ? _self.ipfsCid : ipfsCid // ignore: cast_nullable_to_non_nullable
as String,isSimulated: null == isSimulated ? _self.isSimulated : isSimulated // ignore: cast_nullable_to_non_nullable
as bool,hourly: null == hourly ? _self._hourly : hourly // ignore: cast_nullable_to_non_nullable
as List<WrfForecastPoint>,
  ));
}


}

// dart format on
