import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/wrf_units.dart';
import '../../data/models/wallet_model.dart';
import 'wallet_provider.dart';

/// The wallet's lifetime earned total as display WRF, for example `"1.5"`.
///
/// The only source is the public balance read's `earned` field: base units,
/// 8 decimals. A submit answer's `rewardAmount` is that same lifetime total,
/// so it is never added up per reading. Null when there is no wallet, the
/// read failed, or the node did not report it.
String? walletEarnedWrfDisplay(WalletModel? wallet) {
  final earned = wallet?.earnedBalanceTotal;
  return earned == null ? null : wrfBaseUnitsToDisplay(earned);
}

final walletEarnedWrfProvider = FutureProvider<String?>((ref) async {
  try {
    return walletEarnedWrfDisplay(await ref.watch(walletProvider.future));
  } catch (_) {
    return null;
  }
});
