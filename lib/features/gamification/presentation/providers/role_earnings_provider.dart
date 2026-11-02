import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/crypto/key_manager.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
import '../../../../core/auth/auth_handoff.dart';
import '../../data/models/role_earnings_model.dart';
import '../../data/repositories/role_earnings_repository.dart';

final earningsReadProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(roleEarningsRepositoryProvider).enabled(),
  retry: (_, _) => null,
);

class RoleBoardState {
  final EarningsRole role;
  final EarningsPeriod period;
  final bool loading, failed;
  final RoleLeaderboard? board;
  const RoleBoardState({
    this.role = EarningsRole.producer,
    this.period = EarningsPeriod.all,
    this.loading = false,
    this.failed = false,
    this.board,
  });
}

class RoleBoardNotifier extends Notifier<RoleBoardState> {
  int _request = 0;
  @override
  RoleBoardState build() {
    return const RoleBoardState();
  }

  Future<void> load({EarningsRole? role, EarningsPeriod? period}) async {
    final request = ++_request;
    final nextRole = role ?? state.role, nextPeriod = period ?? state.period;
    state = RoleBoardState(role: nextRole, period: nextPeriod, loading: true);
    try {
      if (!await ref.read(earningsReadProvider.future)) {
        if (ref.mounted && request == _request) {
          state = RoleBoardState(
            role: nextRole,
            period: nextPeriod,
            failed: true,
          );
        }
        return;
      }
      if (!ref.mounted || request != _request) return;
      final board = await ref
          .read(roleEarningsRepositoryProvider)
          .leaderboard(nextRole, nextPeriod);
      if (!ref.mounted || request != _request) return;
      state = RoleBoardState(role: nextRole, period: nextPeriod, board: board);
    } catch (_) {
      if (ref.mounted && request == _request) {
        state = RoleBoardState(
          role: nextRole,
          period: nextPeriod,
          failed: true,
        );
      }
    }
  }
}

final roleBoardProvider = NotifierProvider<RoleBoardNotifier, RoleBoardState>(
  RoleBoardNotifier.new,
);
final ownEarningsAddressProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  if (ref.watch(authHandoffControllerProvider).requiresWalletConnect) {
    return null;
  }
  // Wallet creation/import/wipe invalidates this dependency and drops the
  // previous identity before reading the authenticated login address.
  final wallet = await ref.watch(walletProvider.future);
  if (wallet == null || !ref.mounted) return null;
  return ref.watch(keyManagerProvider).getLoginAddress();
});
final ownRoleEarningsProvider = FutureProvider.autoDispose<OwnRoleEarnings?>((
  ref,
) async {
  if (!await ref.watch(earningsReadProvider.future)) return null;
  final address = await ref.watch(ownEarningsAddressProvider.future);
  if (address == null) return null;
  return ref.watch(roleEarningsRepositoryProvider).ownEarnings();
});
