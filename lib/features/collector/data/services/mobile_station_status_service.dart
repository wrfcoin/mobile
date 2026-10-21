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

  static const awaitingActivationMessage =
      'Station awaiting activation. Rewards start once the network activates your station.';

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
      MobileStationPhase.none => 'Register your phone as a weather station. Collect Now asks for one wallet approval to enable uploads.',
      MobileStationPhase.dbOnly ||
      MobileStationPhase.submitted => awaitingActivationMessage,
      MobileStationPhase.onChain => null,
      MobileStationPhase.unknown => 'Station status is not available. Readings stay saved if registration or upload cannot complete.',
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
