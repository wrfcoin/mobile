import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/crypto/station_signing.dart';
import '../../../collector/data/services/station_owner_api.dart';
import '../../data/models/duel_model.dart';
import '../../data/repositories/duel_repository.dart';

final duelBoardProvider =
    FutureProvider.autoDispose<Either<Failure, DuelBoard>>(
      (ref) => ref.watch(duelRepositoryProvider).getBoard(),
    );

final duelProvider = FutureProvider.autoDispose
    .family<Either<Failure, Duel>, String>(
      (ref, id) => ref.watch(duelRepositoryProvider).getDuel(id),
    );

/// This device's wallet, lowercase, or null without one. For display and for
/// offering actions only; the server decides from the login token.
final duelWalletProvider = FutureProvider.autoDispose<String?>((ref) async {
  final address = await ref.watch(keyManagerProvider).getAddress();
  final clean = address?.trim().toLowerCase();
  return clean == null || clean.isEmpty ? null : clean;
});

/// The public alias of this phone's own station, derived from [wallet].
String phoneStationAlias(String wallet) =>
    stationAliasOf(deriveMobileStationId(wallet));
