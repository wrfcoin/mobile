// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'wallet_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WalletModel {

 String get address; String get balance; String? get stakingRewards; String? get weatherRewards;/// Chain amounts are integer base-unit strings; null means unreported.
 String? get earnedBalanceTotal; String? get weatherRewardsPending; String? get weatherRewardsUnavailable; int get transactions; int get nonce; double get reputationScore; int get pendingTransactions; int get dataSubmissions;
/// Create a copy of WalletModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WalletModelCopyWith<WalletModel> get copyWith => _$WalletModelCopyWithImpl<WalletModel>(this as WalletModel, _$identity);

  /// Serializes this WalletModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WalletModel&&(identical(other.address, address) || other.address == address)&&(identical(other.balance, balance) || other.balance == balance)&&(identical(other.stakingRewards, stakingRewards) || other.stakingRewards == stakingRewards)&&(identical(other.weatherRewards, weatherRewards) || other.weatherRewards == weatherRewards)&&(identical(other.earnedBalanceTotal, earnedBalanceTotal) || other.earnedBalanceTotal == earnedBalanceTotal)&&(identical(other.weatherRewardsPending, weatherRewardsPending) || other.weatherRewardsPending == weatherRewardsPending)&&(identical(other.weatherRewardsUnavailable, weatherRewardsUnavailable) || other.weatherRewardsUnavailable == weatherRewardsUnavailable)&&(identical(other.transactions, transactions) || other.transactions == transactions)&&(identical(other.nonce, nonce) || other.nonce == nonce)&&(identical(other.reputationScore, reputationScore) || other.reputationScore == reputationScore)&&(identical(other.pendingTransactions, pendingTransactions) || other.pendingTransactions == pendingTransactions)&&(identical(other.dataSubmissions, dataSubmissions) || other.dataSubmissions == dataSubmissions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,address,balance,stakingRewards,weatherRewards,earnedBalanceTotal,weatherRewardsPending,weatherRewardsUnavailable,transactions,nonce,reputationScore,pendingTransactions,dataSubmissions);

@override
String toString() {
  return 'WalletModel(address: $address, balance: $balance, stakingRewards: $stakingRewards, weatherRewards: $weatherRewards, earnedBalanceTotal: $earnedBalanceTotal, weatherRewardsPending: $weatherRewardsPending, weatherRewardsUnavailable: $weatherRewardsUnavailable, transactions: $transactions, nonce: $nonce, reputationScore: $reputationScore, pendingTransactions: $pendingTransactions, dataSubmissions: $dataSubmissions)';
}


}

/// @nodoc
abstract mixin class $WalletModelCopyWith<$Res>  {
  factory $WalletModelCopyWith(WalletModel value, $Res Function(WalletModel) _then) = _$WalletModelCopyWithImpl;
@useResult
$Res call({
 String address, String balance, String? stakingRewards, String? weatherRewards, String? earnedBalanceTotal, String? weatherRewardsPending, String? weatherRewardsUnavailable, int transactions, int nonce, double reputationScore, int pendingTransactions, int dataSubmissions
});




}
/// @nodoc
class _$WalletModelCopyWithImpl<$Res>
    implements $WalletModelCopyWith<$Res> {
  _$WalletModelCopyWithImpl(this._self, this._then);

  final WalletModel _self;
  final $Res Function(WalletModel) _then;

/// Create a copy of WalletModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? address = null,Object? balance = null,Object? stakingRewards = freezed,Object? weatherRewards = freezed,Object? earnedBalanceTotal = freezed,Object? weatherRewardsPending = freezed,Object? weatherRewardsUnavailable = freezed,Object? transactions = null,Object? nonce = null,Object? reputationScore = null,Object? pendingTransactions = null,Object? dataSubmissions = null,}) {
  return _then(WalletModel(
address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as String,stakingRewards: freezed == stakingRewards ? _self.stakingRewards : stakingRewards // ignore: cast_nullable_to_non_nullable
as String?,weatherRewards: freezed == weatherRewards ? _self.weatherRewards : weatherRewards // ignore: cast_nullable_to_non_nullable
as String?,earnedBalanceTotal: freezed == earnedBalanceTotal ? _self.earnedBalanceTotal : earnedBalanceTotal // ignore: cast_nullable_to_non_nullable
as String?,weatherRewardsPending: freezed == weatherRewardsPending ? _self.weatherRewardsPending : weatherRewardsPending // ignore: cast_nullable_to_non_nullable
as String?,weatherRewardsUnavailable: freezed == weatherRewardsUnavailable ? _self.weatherRewardsUnavailable : weatherRewardsUnavailable // ignore: cast_nullable_to_non_nullable
as String?,transactions: null == transactions ? _self.transactions : transactions // ignore: cast_nullable_to_non_nullable
as int,nonce: null == nonce ? _self.nonce : nonce // ignore: cast_nullable_to_non_nullable
as int,reputationScore: null == reputationScore ? _self.reputationScore : reputationScore // ignore: cast_nullable_to_non_nullable
as double,pendingTransactions: null == pendingTransactions ? _self.pendingTransactions : pendingTransactions // ignore: cast_nullable_to_non_nullable
as int,dataSubmissions: null == dataSubmissions ? _self.dataSubmissions : dataSubmissions // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [WalletModel].
extension WalletModelPatterns on WalletModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WalletModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WalletModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WalletModel value)  $default,){
final _that = this;
switch (_that) {
case _WalletModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WalletModel value)?  $default,){
final _that = this;
switch (_that) {
case _WalletModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String address,  String balance,  String? stakingRewards,  String? weatherRewards,  String? earnedBalanceTotal,  String? weatherRewardsPending,  String? weatherRewardsUnavailable,  int transactions,  int nonce,  double reputationScore,  int pendingTransactions,  int dataSubmissions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WalletModel() when $default != null:
return $default(_that.address,_that.balance,_that.stakingRewards,_that.weatherRewards,_that.earnedBalanceTotal,_that.weatherRewardsPending,_that.weatherRewardsUnavailable,_that.transactions,_that.nonce,_that.reputationScore,_that.pendingTransactions,_that.dataSubmissions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String address,  String balance,  String? stakingRewards,  String? weatherRewards,  String? earnedBalanceTotal,  String? weatherRewardsPending,  String? weatherRewardsUnavailable,  int transactions,  int nonce,  double reputationScore,  int pendingTransactions,  int dataSubmissions)  $default,) {final _that = this;
switch (_that) {
case _WalletModel():
return $default(_that.address,_that.balance,_that.stakingRewards,_that.weatherRewards,_that.earnedBalanceTotal,_that.weatherRewardsPending,_that.weatherRewardsUnavailable,_that.transactions,_that.nonce,_that.reputationScore,_that.pendingTransactions,_that.dataSubmissions);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String address,  String balance,  String? stakingRewards,  String? weatherRewards,  String? earnedBalanceTotal,  String? weatherRewardsPending,  String? weatherRewardsUnavailable,  int transactions,  int nonce,  double reputationScore,  int pendingTransactions,  int dataSubmissions)?  $default,) {final _that = this;
switch (_that) {
case _WalletModel() when $default != null:
return $default(_that.address,_that.balance,_that.stakingRewards,_that.weatherRewards,_that.earnedBalanceTotal,_that.weatherRewardsPending,_that.weatherRewardsUnavailable,_that.transactions,_that.nonce,_that.reputationScore,_that.pendingTransactions,_that.dataSubmissions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WalletModel implements WalletModel {
  const _WalletModel({required this.address, required this.balance, this.stakingRewards, this.weatherRewards, this.earnedBalanceTotal, this.weatherRewardsPending, this.weatherRewardsUnavailable, this.transactions = 0, this.nonce = 0, this.reputationScore = 0.0, this.pendingTransactions = 0, this.dataSubmissions = 0});
  factory _WalletModel.fromJson(Map<String, dynamic> json) => _$WalletModelFromJson(json);

@override final  String address;
@override final  String balance;
@override final  String? stakingRewards;
@override final  String? weatherRewards;
/// Chain amounts are integer base-unit strings; null means unreported.
@override final  String? earnedBalanceTotal;
@override final  String? weatherRewardsPending;
@override final  String? weatherRewardsUnavailable;
@override@JsonKey() final  int transactions;
@override@JsonKey() final  int nonce;
@override@JsonKey() final  double reputationScore;
@override@JsonKey() final  int pendingTransactions;
@override@JsonKey() final  int dataSubmissions;

/// Create a copy of WalletModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WalletModelCopyWith<_WalletModel> get copyWith => __$WalletModelCopyWithImpl<_WalletModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WalletModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WalletModel&&(identical(other.address, address) || other.address == address)&&(identical(other.balance, balance) || other.balance == balance)&&(identical(other.stakingRewards, stakingRewards) || other.stakingRewards == stakingRewards)&&(identical(other.weatherRewards, weatherRewards) || other.weatherRewards == weatherRewards)&&(identical(other.earnedBalanceTotal, earnedBalanceTotal) || other.earnedBalanceTotal == earnedBalanceTotal)&&(identical(other.weatherRewardsPending, weatherRewardsPending) || other.weatherRewardsPending == weatherRewardsPending)&&(identical(other.weatherRewardsUnavailable, weatherRewardsUnavailable) || other.weatherRewardsUnavailable == weatherRewardsUnavailable)&&(identical(other.transactions, transactions) || other.transactions == transactions)&&(identical(other.nonce, nonce) || other.nonce == nonce)&&(identical(other.reputationScore, reputationScore) || other.reputationScore == reputationScore)&&(identical(other.pendingTransactions, pendingTransactions) || other.pendingTransactions == pendingTransactions)&&(identical(other.dataSubmissions, dataSubmissions) || other.dataSubmissions == dataSubmissions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,address,balance,stakingRewards,weatherRewards,earnedBalanceTotal,weatherRewardsPending,weatherRewardsUnavailable,transactions,nonce,reputationScore,pendingTransactions,dataSubmissions);

@override
String toString() {
  return 'WalletModel(address: $address, balance: $balance, stakingRewards: $stakingRewards, weatherRewards: $weatherRewards, earnedBalanceTotal: $earnedBalanceTotal, weatherRewardsPending: $weatherRewardsPending, weatherRewardsUnavailable: $weatherRewardsUnavailable, transactions: $transactions, nonce: $nonce, reputationScore: $reputationScore, pendingTransactions: $pendingTransactions, dataSubmissions: $dataSubmissions)';
}


}

/// @nodoc
abstract mixin class _$WalletModelCopyWith<$Res> implements $WalletModelCopyWith<$Res> {
  factory _$WalletModelCopyWith(_WalletModel value, $Res Function(_WalletModel) _then) = __$WalletModelCopyWithImpl;
@override @useResult
$Res call({
 String address, String balance, String? stakingRewards, String? weatherRewards, String? earnedBalanceTotal, String? weatherRewardsPending, String? weatherRewardsUnavailable, int transactions, int nonce, double reputationScore, int pendingTransactions, int dataSubmissions
});




}
/// @nodoc
class __$WalletModelCopyWithImpl<$Res>
    implements _$WalletModelCopyWith<$Res> {
  __$WalletModelCopyWithImpl(this._self, this._then);

  final _WalletModel _self;
  final $Res Function(_WalletModel) _then;

/// Create a copy of WalletModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? address = null,Object? balance = null,Object? stakingRewards = freezed,Object? weatherRewards = freezed,Object? earnedBalanceTotal = freezed,Object? weatherRewardsPending = freezed,Object? weatherRewardsUnavailable = freezed,Object? transactions = null,Object? nonce = null,Object? reputationScore = null,Object? pendingTransactions = null,Object? dataSubmissions = null,}) {
  return _then(_WalletModel(
address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as String,stakingRewards: freezed == stakingRewards ? _self.stakingRewards : stakingRewards // ignore: cast_nullable_to_non_nullable
as String?,weatherRewards: freezed == weatherRewards ? _self.weatherRewards : weatherRewards // ignore: cast_nullable_to_non_nullable
as String?,earnedBalanceTotal: freezed == earnedBalanceTotal ? _self.earnedBalanceTotal : earnedBalanceTotal // ignore: cast_nullable_to_non_nullable
as String?,weatherRewardsPending: freezed == weatherRewardsPending ? _self.weatherRewardsPending : weatherRewardsPending // ignore: cast_nullable_to_non_nullable
as String?,weatherRewardsUnavailable: freezed == weatherRewardsUnavailable ? _self.weatherRewardsUnavailable : weatherRewardsUnavailable // ignore: cast_nullable_to_non_nullable
as String?,transactions: null == transactions ? _self.transactions : transactions // ignore: cast_nullable_to_non_nullable
as int,nonce: null == nonce ? _self.nonce : nonce // ignore: cast_nullable_to_non_nullable
as int,reputationScore: null == reputationScore ? _self.reputationScore : reputationScore // ignore: cast_nullable_to_non_nullable
as double,pendingTransactions: null == pendingTransactions ? _self.pendingTransactions : pendingTransactions // ignore: cast_nullable_to_non_nullable
as int,dataSubmissions: null == dataSubmissions ? _self.dataSubmissions : dataSubmissions // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
