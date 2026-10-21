// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'forecast_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ForecastModel {

 double? get temperature; double? get humidity; double? get pressure; double? get windSpeed; String? get windDirection; double? get precipitation; int? get aqi; double? get wildfireRisk; String get location; String get timestamp;
/// Create a copy of ForecastModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ForecastModelCopyWith<ForecastModel> get copyWith => _$ForecastModelCopyWithImpl<ForecastModel>(this as ForecastModel, _$identity);

  /// Serializes this ForecastModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ForecastModel&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.humidity, humidity) || other.humidity == humidity)&&(identical(other.pressure, pressure) || other.pressure == pressure)&&(identical(other.windSpeed, windSpeed) || other.windSpeed == windSpeed)&&(identical(other.windDirection, windDirection) || other.windDirection == windDirection)&&(identical(other.precipitation, precipitation) || other.precipitation == precipitation)&&(identical(other.aqi, aqi) || other.aqi == aqi)&&(identical(other.wildfireRisk, wildfireRisk) || other.wildfireRisk == wildfireRisk)&&(identical(other.location, location) || other.location == location)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,temperature,humidity,pressure,windSpeed,windDirection,precipitation,aqi,wildfireRisk,location,timestamp);

@override
String toString() {
  return 'ForecastModel(temperature: $temperature, humidity: $humidity, pressure: $pressure, windSpeed: $windSpeed, windDirection: $windDirection, precipitation: $precipitation, aqi: $aqi, wildfireRisk: $wildfireRisk, location: $location, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class $ForecastModelCopyWith<$Res>  {
  factory $ForecastModelCopyWith(ForecastModel value, $Res Function(ForecastModel) _then) = _$ForecastModelCopyWithImpl;
@useResult
$Res call({
 double? temperature, double? humidity, double? pressure, double? windSpeed, String? windDirection, double? precipitation, int? aqi, double? wildfireRisk, String location, String timestamp
});




}
/// @nodoc
class _$ForecastModelCopyWithImpl<$Res>
    implements $ForecastModelCopyWith<$Res> {
  _$ForecastModelCopyWithImpl(this._self, this._then);

  final ForecastModel _self;
  final $Res Function(ForecastModel) _then;

/// Create a copy of ForecastModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? temperature = freezed,Object? humidity = freezed,Object? pressure = freezed,Object? windSpeed = freezed,Object? windDirection = freezed,Object? precipitation = freezed,Object? aqi = freezed,Object? wildfireRisk = freezed,Object? location = null,Object? timestamp = null,}) {
  return _then(ForecastModel(
temperature: freezed == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double?,humidity: freezed == humidity ? _self.humidity : humidity // ignore: cast_nullable_to_non_nullable
as double?,pressure: freezed == pressure ? _self.pressure : pressure // ignore: cast_nullable_to_non_nullable
as double?,windSpeed: freezed == windSpeed ? _self.windSpeed : windSpeed // ignore: cast_nullable_to_non_nullable
as double?,windDirection: freezed == windDirection ? _self.windDirection : windDirection // ignore: cast_nullable_to_non_nullable
as String?,precipitation: freezed == precipitation ? _self.precipitation : precipitation // ignore: cast_nullable_to_non_nullable
as double?,aqi: freezed == aqi ? _self.aqi : aqi // ignore: cast_nullable_to_non_nullable
as int?,wildfireRisk: freezed == wildfireRisk ? _self.wildfireRisk : wildfireRisk // ignore: cast_nullable_to_non_nullable
as double?,location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ForecastModel].
extension ForecastModelPatterns on ForecastModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ForecastModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ForecastModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ForecastModel value)  $default,){
final _that = this;
switch (_that) {
case _ForecastModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ForecastModel value)?  $default,){
final _that = this;
switch (_that) {
case _ForecastModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double? temperature,  double? humidity,  double? pressure,  double? windSpeed,  String? windDirection,  double? precipitation,  int? aqi,  double? wildfireRisk,  String location,  String timestamp)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ForecastModel() when $default != null:
return $default(_that.temperature,_that.humidity,_that.pressure,_that.windSpeed,_that.windDirection,_that.precipitation,_that.aqi,_that.wildfireRisk,_that.location,_that.timestamp);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double? temperature,  double? humidity,  double? pressure,  double? windSpeed,  String? windDirection,  double? precipitation,  int? aqi,  double? wildfireRisk,  String location,  String timestamp)  $default,) {final _that = this;
switch (_that) {
case _ForecastModel():
return $default(_that.temperature,_that.humidity,_that.pressure,_that.windSpeed,_that.windDirection,_that.precipitation,_that.aqi,_that.wildfireRisk,_that.location,_that.timestamp);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double? temperature,  double? humidity,  double? pressure,  double? windSpeed,  String? windDirection,  double? precipitation,  int? aqi,  double? wildfireRisk,  String location,  String timestamp)?  $default,) {final _that = this;
switch (_that) {
case _ForecastModel() when $default != null:
return $default(_that.temperature,_that.humidity,_that.pressure,_that.windSpeed,_that.windDirection,_that.precipitation,_that.aqi,_that.wildfireRisk,_that.location,_that.timestamp);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ForecastModel implements ForecastModel {
  const _ForecastModel({this.temperature, this.humidity, this.pressure, this.windSpeed, this.windDirection, this.precipitation, this.aqi, this.wildfireRisk, required this.location, required this.timestamp});
  factory _ForecastModel.fromJson(Map<String, dynamic> json) => _$ForecastModelFromJson(json);

@override final  double? temperature;
@override final  double? humidity;
@override final  double? pressure;
@override final  double? windSpeed;
@override final  String? windDirection;
@override final  double? precipitation;
@override final  int? aqi;
@override final  double? wildfireRisk;
@override final  String location;
@override final  String timestamp;

/// Create a copy of ForecastModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ForecastModelCopyWith<_ForecastModel> get copyWith => __$ForecastModelCopyWithImpl<_ForecastModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ForecastModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ForecastModel&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.humidity, humidity) || other.humidity == humidity)&&(identical(other.pressure, pressure) || other.pressure == pressure)&&(identical(other.windSpeed, windSpeed) || other.windSpeed == windSpeed)&&(identical(other.windDirection, windDirection) || other.windDirection == windDirection)&&(identical(other.precipitation, precipitation) || other.precipitation == precipitation)&&(identical(other.aqi, aqi) || other.aqi == aqi)&&(identical(other.wildfireRisk, wildfireRisk) || other.wildfireRisk == wildfireRisk)&&(identical(other.location, location) || other.location == location)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,temperature,humidity,pressure,windSpeed,windDirection,precipitation,aqi,wildfireRisk,location,timestamp);

@override
String toString() {
  return 'ForecastModel(temperature: $temperature, humidity: $humidity, pressure: $pressure, windSpeed: $windSpeed, windDirection: $windDirection, precipitation: $precipitation, aqi: $aqi, wildfireRisk: $wildfireRisk, location: $location, timestamp: $timestamp)';
}


}

/// @nodoc
abstract mixin class _$ForecastModelCopyWith<$Res> implements $ForecastModelCopyWith<$Res> {
  factory _$ForecastModelCopyWith(_ForecastModel value, $Res Function(_ForecastModel) _then) = __$ForecastModelCopyWithImpl;
@override @useResult
$Res call({
 double? temperature, double? humidity, double? pressure, double? windSpeed, String? windDirection, double? precipitation, int? aqi, double? wildfireRisk, String location, String timestamp
});




}
/// @nodoc
class __$ForecastModelCopyWithImpl<$Res>
    implements _$ForecastModelCopyWith<$Res> {
  __$ForecastModelCopyWithImpl(this._self, this._then);

  final _ForecastModel _self;
  final $Res Function(_ForecastModel) _then;

/// Create a copy of ForecastModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? temperature = freezed,Object? humidity = freezed,Object? pressure = freezed,Object? windSpeed = freezed,Object? windDirection = freezed,Object? precipitation = freezed,Object? aqi = freezed,Object? wildfireRisk = freezed,Object? location = null,Object? timestamp = null,}) {
  return _then(_ForecastModel(
temperature: freezed == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double?,humidity: freezed == humidity ? _self.humidity : humidity // ignore: cast_nullable_to_non_nullable
as double?,pressure: freezed == pressure ? _self.pressure : pressure // ignore: cast_nullable_to_non_nullable
as double?,windSpeed: freezed == windSpeed ? _self.windSpeed : windSpeed // ignore: cast_nullable_to_non_nullable
as double?,windDirection: freezed == windDirection ? _self.windDirection : windDirection // ignore: cast_nullable_to_non_nullable
as String?,precipitation: freezed == precipitation ? _self.precipitation : precipitation // ignore: cast_nullable_to_non_nullable
as double?,aqi: freezed == aqi ? _self.aqi : aqi // ignore: cast_nullable_to_non_nullable
as int?,wildfireRisk: freezed == wildfireRisk ? _self.wildfireRisk : wildfireRisk // ignore: cast_nullable_to_non_nullable
as double?,location: null == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
