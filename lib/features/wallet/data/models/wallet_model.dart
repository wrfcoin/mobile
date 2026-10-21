import 'package:freezed_annotation/freezed_annotation.dart';

part 'wallet_model.freezed.dart';
part 'wallet_model.g.dart';

@Freezed()
sealed class WalletModel with _$WalletModel {
  const factory WalletModel({
    required String address,
    required String balance,
    String? stakingRewards,
    String? weatherRewards,

    /// Chain amounts are integer base-unit strings; null means unreported.
    String? earnedBalanceTotal,
    String? weatherRewardsPending,
    String? weatherRewardsUnavailable,
    @Default(0) int transactions,
    @Default(0) int nonce,
    @Default(0.0) double reputationScore,
    @Default(0) int pendingTransactions,
    @Default(0) int dataSubmissions,
  }) = _WalletModel;

  factory WalletModel.fromJson(Map<String, dynamic> json) =>
      _$WalletModelFromJson(json);
}
