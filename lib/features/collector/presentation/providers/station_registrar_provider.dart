import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/api_client.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/crypto/station_signing.dart';
import '../../data/services/station_registrar_service.dart';

final stationRegistrarServiceProvider = Provider<StationRegistrarService>(
  (ref) => StationRegistrarService(apiClient: ref.read(apiClientProvider)),
);

/// Opens the one biometric-gated wallet session a request signs with.
final stationRegistrarSessionOpenerProvider =
    Provider<Future<StationSigningSession?> Function()>((ref) {
      final keyManager = ref.read(keyManagerProvider);
      return () => StationSigningService(keyManager: keyManager).openSession();
    });

/// The registrar request status for one station, or null when requests are
/// not open (the card is then not shown). Read only; never signs.
final stationRegistrarStatusProvider = FutureProvider.autoDispose
    .family<RegistrarStatus?, String>(
      (ref, stationId) =>
          ref.read(stationRegistrarServiceProvider).status(stationId),
    );
