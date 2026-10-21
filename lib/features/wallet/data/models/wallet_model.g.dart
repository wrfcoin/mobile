// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wallet_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WalletModel _$WalletModelFromJson(Map<String, dynamic> json) => _WalletModel(
  address: json['address'] as String,
  balance: json['balance'] as String,
  stakingRewards: json['stakingRewards'] as String?,
  weatherRewards: json['weatherRewards'] as String?,
  earnedBalanceTotal: json['earnedBalanceTotal'] as String?,
  weatherRewardsPending: json['weatherRewardsPending'] as String?,
  weatherRewardsUnavailable: json['weatherRewardsUnavailable'] as String?,
  transactions: (json['transactions'] as num?)?.toInt() ?? 0,
  nonce: (json['nonce'] as num?)?.toInt() ?? 0,
  reputationScore: (json['reputationScore'] as num?)?.toDouble() ?? 0.0,
  pendingTransactions: (json['pendingTransactions'] as num?)?.toInt() ?? 0,
  dataSubmissions: (json['dataSubmissions'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$WalletModelToJson(_WalletModel instance) =>
    <String, dynamic>{
      'address': instance.address,
      'balance': instance.balance,
      'stakingRewards': instance.stakingRewards,
      'weatherRewards': instance.weatherRewards,
      'earnedBalanceTotal': instance.earnedBalanceTotal,
      'weatherRewardsPending': instance.weatherRewardsPending,
      'weatherRewardsUnavailable': instance.weatherRewardsUnavailable,
      'transactions': instance.transactions,
      'nonce': instance.nonce,
      'reputationScore': instance.reputationScore,
      'pendingTransactions': instance.pendingTransactions,
      'dataSubmissions': instance.dataSubmissions,
    };
