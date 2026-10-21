import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../wallet/presentation/providers/wallet_provider.dart';
import '../../data/models/station_owner_models.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/crypto/station_signing.dart';
import '../../data/services/station_owner_api.dart';
import '../../data/services/station_owner_service.dart';

final stationOwnerServiceProvider = Provider<StationOwnerService>((ref) {
  final keyManager = ref.read(keyManagerProvider);
  return StationOwnerService(
    api: DioStationOwnerApi(ref.read(apiClientProvider).dio),
    openSession: () =>
        StationSigningService(keyManager: keyManager).openSession(),
  );
});

/// Fixed user text for any owner-action failure. Server messages are never
/// shown, and a failure never reads as success.
String stationOwnerErrorText(Object error) {
  if (error is StationOwnerCancelled) {
    return 'Cancelled. Nothing was signed.';
  }
  if (error is StationOwnerBlocked) return error.reason;
  if (error is OfferRejected) return error.problem.message;
  if (error is StationOwnerException) {
    return error.network
        ? 'No connection. Nothing was changed.'
        : error.refusal.userMessage;
  }
  if (error is StationSigningUnavailable ||
      error is StationSigningForegroundRequired) {
    return 'This wallet cannot sign station changes right now.';
  }
  return 'Something went wrong. Nothing was changed.';
}

/// Ledger state of THIS wallet's own station (read only, no biometric).
/// Errors propagate: a failed read is "unavailable", never "normal".
final ownerStationLedgerProvider = FutureProvider.autoDispose<OwnerLedger>(
  retry: (_, _) => null,
  (ref) async {
    final address = (await ref.watch(walletProvider.future))?.address;
    if (address == null) {
      throw const StationOwnerException(StationOwnerRefusal.loginRequired);
    }
    return ref
        .read(stationOwnerServiceProvider)
        .api
        .readLedger(deriveMobileStationId(address.trim().toLowerCase()));
  },
);
