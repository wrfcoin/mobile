import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/crypto/station_signing.dart';
import '../../../../services/storage/local_db.dart';

enum MobileStationPhase { none, dbOnly, submitted, onChain, unknown }

class MobileStationStatus {
  const MobileStationStatus(this.phase, {this.cached = false});
  final MobileStationPhase phase;
  final bool cached;

  /// True to `SyncWorker`: while waiting, the backend refuses uploads, and
  /// everything unsynced is deleted at each check and again at activation
  /// (`dropUnactivatedReadingsWithNotice`). So this must not call them saved.
  static const awaitingActivationMessage =
      'Your station is registered and waiting for the network to activate it. '
      'Nothing is wrong, and you don\'t need to do anything. There\'s no set '
      'time for this. Readings taken before activation can\'t earn and are '
      'removed from this phone. Rewards can start with readings taken after '
      'it activates.';

  /// Shown until the one foreground approval has registered this phone. A
  /// background run cannot open the wallet, so nothing uploads before the
  /// user taps Collect Now and approves; say exactly that.
  static const notRegisteredMessage =
      'One step left before this phone can earn: register it as a weather '
      'station. Turn collection on, tap Collect Now, and approve once with '
      'your fingerprint or PIN. Nothing uploads until you do.';

  /// True to `SyncWorker.maxReadingAge`: a reading is kept 50 minutes, then
  /// dropped, whatever the reason it could not upload.
  static const statusUnavailableMessage =
      'Station status is not available right now. The app keeps trying. '
      'Readings wait for up to 50 minutes; older ones can\'t earn and are '
      'removed.';

  /// The server said this station is not active yet: not a failed or stale check.
  bool get isAwaitingActivation =>
      !cached &&
      (phase == MobileStationPhase.dbOnly ||
          phase == MobileStationPhase.submitted);

  String? get message {
    if (cached) {
      final lastKnown = switch (phase) {
        MobileStationPhase.none => 'not registered',
        MobileStationPhase.dbOnly ||
        MobileStationPhase.submitted => 'registered, pending activation',
        MobileStationPhase.onChain => 'on chain',
        MobileStationPhase.unknown => 'not available',
      };
      return 'Station status could not be refreshed. Last known status: $lastKnown; rewards are not confirmed.';
    }
    return switch (phase) {
      MobileStationPhase.none => notRegisteredMessage,
      MobileStationPhase.dbOnly ||
      MobileStationPhase.submitted => awaitingActivationMessage,
      MobileStationPhase.onChain => null,
      MobileStationPhase.unknown => statusUnavailableMessage,
    };
  }
}

/// Reads only the caller's status endpoint. Cache entries are bound to the
/// locally derived station id; errors never manufacture an activation state.
class MobileStationStatusService {
  const MobileStationStatusService({required this.apiClient, this.db});
  final ApiClient apiClient;
  final AppDatabase? db;

  static String cacheKey(String stationId) =>
      'mobile_station_status:$stationId';

  static MobileStationPhase? _phase(Object? value) => switch (value) {
    'none' => MobileStationPhase.none,
    'db_only' => MobileStationPhase.dbOnly,
    'submitted' => MobileStationPhase.submitted,
    'on_chain' => MobileStationPhase.onChain,
    _ => null,
  };

  Future<MobileStationStatus> fetch(String owner) async {
    final String stationId;
    try {
      stationId = deriveMobileStationId(owner.trim().toLowerCase());
    } on ArgumentError {
      return const MobileStationStatus(MobileStationPhase.unknown);
    }
    try {
      final response = await apiClient.dio.get<dynamic>(
        ApiConstants.mobileStationRegister,
      );
      final data = response.data;
      final phase = data is Map ? _phase(data['status']) : null;
      if (data is! Map ||
          data['stationId'] != stationId ||
          phase == null ||
          phase == MobileStationPhase.none) {
        throw const FormatException('Unexpected station status');
      }
      await _remember(stationId, data['status'] as String);
      return MobileStationStatus(phase);
    } on DioException catch (error) {
      final body = error.response?.data;
      final code = body is Map && body['error'] is Map
          ? (body['error'] as Map)['code']
          : null;
      if (error.response?.statusCode == 404 && code == 'NOT_REGISTERED') {
        await _remember(stationId, 'none');
        return const MobileStationStatus(MobileStationPhase.none);
      }
      return _cached(stationId);
    } catch (_) {
      return _cached(stationId);
    }
  }

  Future<void> _remember(String stationId, String status) async {
    try {
      await db?.upsertOfflineData(
        cacheKey(stationId),
        jsonEncode({'stationId': stationId, 'status': status}),
      );
    } catch (_) {
      // A cache write failure does not change a verified live response.
    }
  }

  Future<MobileStationStatus> _cached(String stationId) async {
    try {
      final entry = await db?.getOfflineData(cacheKey(stationId));
      final data = entry == null ? null : jsonDecode(entry.payload);
      final phase = data is Map && data['stationId'] == stationId
          ? _phase(data['status'])
          : null;
      if (phase != null) return MobileStationStatus(phase, cached: true);
    } catch (_) {}
    return const MobileStationStatus(MobileStationPhase.unknown);
  }
}
