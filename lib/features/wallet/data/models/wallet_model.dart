import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/utils/wrf_units.dart';

part 'wallet_model.freezed.dart';
part 'wallet_model.g.dart';

/// Whether the public balance read answered.
///
/// [unavailable]: public reads are switched off (404) or the answer was not
/// usable. [busy]: the API is rate limiting (429). Neither carries a balance;
/// the app never stands in a zero.
enum BalanceAvailability { reported, unavailable, busy }

@Freezed()
sealed class WalletModel with _$WalletModel {
  const factory WalletModel({
    required String address,

    /// Integer base-unit string (1 WRF = 10^8); null when not reported.
    required String? balance,
    @Default(BalanceAvailability.reported)
    BalanceAvailability balanceAvailability,

    /// Chain height the balance was read at; null when not reported.
    int? height,
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

/// Display text for a balance read: `1.5 WRF`, `Busy` (429) or `Unavailable`
/// (404, or nothing usable). Never a stand-in zero.
String walletBalanceText(String? balance, BalanceAvailability availability) {
  if (availability == BalanceAvailability.busy) return 'Busy';
  final display = balance == null ? null : wrfBaseUnitsToDisplay(balance);
  if (availability != BalanceAvailability.reported || display == null) {
    return 'Unavailable';
  }
  return '$display WRF';
}

extension WalletBalanceText on WalletModel {
  String get balanceText => walletBalanceText(balance, balanceAvailability);
}
