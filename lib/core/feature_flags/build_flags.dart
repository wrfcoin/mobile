import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time gate for the wallet Send flow (owner ruling 2026-09-27,
/// mobile#44).
///
/// The relay nonce handling from core4#3337 was repaired by core4#3339 and
/// core4#3340 and shipped in r18. Send remains an owner-selected build option:
/// sideloaded **profile** builds, including the tester APKs from
/// `scripts/build_profile_apk.sh`, hide Send by default. The owner enables
/// live-send acceptance with `--dart-define=WRFCOIN_WALLET_SEND=on` per build.
/// Debug builds (development, the local-stack E2E) and release builds keep
/// their current behaviour.
///
/// `--dart-define=WRFCOIN_WALLET_SEND=on|off` overrides the default in any
/// mode. Any other non-empty value hides Send (fail closed).
class WalletSendGate {
  const WalletSendGate._();

  static const String defineName = 'WRFCOIN_WALLET_SEND';
  static const String _override = String.fromEnvironment(defineName);

  static bool resolve({required String override, required bool isProfileMode}) {
    switch (override.trim().toLowerCase()) {
      case '':
        return !isProfileMode;
      case 'on':
        return true;
      default:
        return false;
    }
  }

  static bool get enabled =>
      resolve(override: _override, isProfileMode: kProfileMode);
}

/// Whether this build offers the wallet Send flow. Tests override it.
final walletSendEnabledProvider = Provider<bool>(
  (ref) => WalletSendGate.enabled,
);
