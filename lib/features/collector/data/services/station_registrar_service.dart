import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/crypto/station_signing.dart';

/// Where a registrar request for this phone's station stands.
enum RegistrarState {
  /// The registrar can take a request and none was sent for this station.
  notRequested,

  /// Accepted; held 24 h before it is signed (see [RegistrarStatus.releaseAt]).
  held,

  /// Signed and sent to the chain; waiting to show in the registry.
  submitted,

  /// On chain. The normal station status takes over from here.
  registered,

  /// Not registered by the registrar (for example the station was registered
  /// some other way during the hold).
  refused,

  /// Waiting for the network operator to look at it.
  needsReview,
}

class RegistrarStatus {
  const RegistrarStatus(this.state, {this.releaseAt});
  final RegistrarState state;
  final DateTime? releaseAt;

  static const notRequested = RegistrarStatus(RegistrarState.notRequested);

  /// Fixed text per state. Server messages are never shown.
  String get message => switch (state) {
    RegistrarState.notRequested =>
      'Optional: you can ask the network to register this station now instead of '
          'waiting for the next batch. Your wallet signs once to prove the '
          'station is yours. No account or email is needed.',
    RegistrarState.held =>
      'Request received. It is held for 24 hours as a safety check, then '
          'signed and sent to the chain. Nothing else to do.',
    RegistrarState.submitted =>
      'Sent to the chain. It shows as registered within a few blocks.',
    RegistrarState.registered =>
      'Registered on chain. Activation follows on its own.',
    RegistrarState.refused =>
      'The network did not register this station through a request. It can '
          'still be registered in the next batch.',
    RegistrarState.needsReview =>
      'The network operator is checking this request. Nothing to do.',
  };
}

/// Why a request was not taken. Each maps to fixed user text.
enum RegistrarRefusal {
  closed(
    'Requests are not open right now. Your station stays in line for the next batch.',
  ),
  limit('Too many requests right now. Try again later.'),
  alreadyRequested('This station was already requested.'),
  alreadyRegistered('This station is already registered on chain.'),
  notEligible(
    'This station can\'t be registered by request. It stays in line for the next batch.',
  ),
  ceiling(
    'The testnet has reached its phone station limit for now. Your station stays in line.',
  ),
  notRegistered(
    'Register this phone first: turn collection on and tap Collect Now.',
  ),
  cancelled('Cancelled. Nothing was signed or sent.'),
  network('No connection. Nothing was sent.');

  const RegistrarRefusal(this.userMessage);
  final String userMessage;

  static RegistrarRefusal fromCode(String? code) => switch (code) {
    'DAILY_TOTAL' || 'DAILY_PER_IP' || 'DAILY_PER_CELL' => limit,
    'ALREADY_REQUESTED' => alreadyRequested,
    'STATION_ALREADY_REGISTERED' => alreadyRegistered,
    'STATION_NOT_NEW' || 'REGISTRATION_REFUSED' => notEligible,
    'REGISTRAR_CEILING' => ceiling,
    _ => closed,
  };
}

class RegistrarRequestException implements Exception {
  const RegistrarRequestException(this.refusal);
  final RegistrarRefusal refusal;
  @override
  String toString() => 'RegistrarRequestException(${refusal.name})';
}

/// Asks the station registrar (core4 `station_registrar_key`) to register
/// this wallet's own phone station, and reads where that request stands.
///
/// Fails closed: the request is offered only when the network reports the
/// feature active AND the registrar answers for this station. Any failed or
/// unexpected read hides it. The row is built only from this wallet's own
/// derived station id and the 0.1 degree cell the backend already holds for
/// it; the exact location never leaves the phone.
class StationRegistrarService {
  const StationRegistrarService({required this.apiClient});
  final ApiClient apiClient;

  static const feature = 'station_registrar_key';
  static final _stationId = RegExp(r'^mob-[0-9a-f]{32}$');

  Dio get _dio => apiClient.dio;

  /// True only when the public network status lists [feature] as active.
  Future<bool> featureActive() async {
    try {
      final response = await _dio.get<dynamic>(
        ApiConstants.publicNetworkStatus,
      );
      final data = response.data;
      final upgrades = data is Map ? data['upgrades'] : null;
      if (upgrades is! Map || upgrades['status'] != 'ok') return false;
      final active = upgrades['active'];
      if (active is! List) return false;
      return active.any((e) => e is Map && e['feature'] == feature);
    } catch (_) {
      return false;
    }
  }

  /// This station's request status, or null when requests are not open
  /// (feature inactive, proxy off, service down, or an unexpected answer).
  Future<RegistrarStatus?> status(String stationId) async {
    if (!_stationId.hasMatch(stationId)) return null;
    if (!await featureActive()) return null;
    try {
      final response = await _dio.get<dynamic>(
        ApiConstants.stationRegistrarRequest(stationId),
      );
      return _parse(response.data, stationId);
    } on DioException catch (error) {
      final code = _code(error.response?.data);
      if (error.response?.statusCode == 404 && code == 'NOT_REQUESTED') {
        return RegistrarStatus.notRequested;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Signs this wallet's ownership proof with [session] and sends one request.
  /// Throws [RegistrarRequestException]; never retries on its own.
  Future<RegistrarStatus> request(StationSigningSession session) async {
    final stationId = session.stationId;
    final ({int latE1, int lonE1}) cell;
    try {
      cell = await _registeredCell(stationId);
    } on RegistrarRequestException {
      rethrow;
    } on DioException {
      throw const RegistrarRequestException(RegistrarRefusal.network);
    }
    final ownership = await session.signOwnership();
    final row = buildRow(
      stationId: stationId,
      ownerAddress: session.ownerAddress,
      ownerPubkey: ownership.publicKeyHex,
      ownerSignature: ownership.signatureHex,
      latE1: cell.latE1,
      lonE1: cell.lonE1,
    );
    try {
      final response = await _dio.post<dynamic>(
        ApiConstants.stationRegistrarRequests,
        data: row,
      );
      final status = _parse(response.data, stationId);
      if (status == null || status.state != RegistrarState.held) {
        throw const RegistrarRequestException(RegistrarRefusal.closed);
      }
      return status;
    } on DioException catch (error) {
      if (error.response == null) {
        throw const RegistrarRequestException(RegistrarRefusal.network);
      }
      throw RegistrarRequestException(
        RegistrarRefusal.fromCode(_code(error.response?.data)),
      );
    }
  }

  /// The exact nine-field row the registrar takes (the owner batch's row less
  /// `submitted_at`, which the registrar stamps when it signs).
  static Map<String, Object> buildRow({
    required String stationId,
    required String ownerAddress,
    required String ownerPubkey,
    required String ownerSignature,
    required int latE1,
    required int lonE1,
  }) => <String, Object>{
    'station_id': stationId,
    'owner_address': ownerAddress,
    'owner_pubkey': ownerPubkey,
    'owner_signature': ownerSignature,
    // The cell's grid point, as the owner batch exporter writes it.
    'latitude': latE1 / 10,
    'longitude': lonE1 / 10,
    'hardware_model': 'phone-barometer',
    'provenance_class': 'real',
    'data_quality_tier': 'unverified',
  };

  /// The cell the backend registered for this wallet's station. Only a
  /// registration still waiting for the network can be requested.
  Future<({int latE1, int lonE1})> _registeredCell(String stationId) async {
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(ApiConstants.mobileStationRegister);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw const RegistrarRequestException(RegistrarRefusal.notRegistered);
      }
      rethrow;
    }
    final data = response.data;
    final cell = data is Map ? data['cell'] : null;
    final lat = cell is Map ? cell['latE1'] : null;
    final lon = cell is Map ? cell['lonE1'] : null;
    if (data is! Map || data['stationId'] != stationId) {
      throw const RegistrarRequestException(RegistrarRefusal.notRegistered);
    }
    if (data['status'] != 'db_only') {
      throw const RegistrarRequestException(RegistrarRefusal.notEligible);
    }
    if (lat is! int || lon is! int || lat.abs() > 900 || lon.abs() > 1800) {
      throw const RegistrarRequestException(RegistrarRefusal.notEligible);
    }
    return (latE1: lat, lonE1: lon);
  }

  static String? _code(Object? body) {
    final error = body is Map ? body['error'] : null;
    final code = error is Map ? error['code'] : null;
    return code is String ? code : null;
  }

  static RegistrarStatus? _parse(Object? body, String stationId) {
    final data = body is Map ? body['data'] : null;
    if (data is! Map || data['stationId'] != stationId) return null;
    final state = switch (data['status']) {
      'held' => RegistrarState.held,
      'submitted' => RegistrarState.submitted,
      'registered' => RegistrarState.registered,
      'refused' => RegistrarState.refused,
      'needs_review' => RegistrarState.needsReview,
      _ => null,
    };
    if (state == null) return null;
    final releaseAt = data['releaseAt'];
    final when = releaseAt is String ? DateTime.tryParse(releaseAt) : null;
    if (state == RegistrarState.held && when == null) return null;
    return RegistrarStatus(state, releaseAt: when);
  }
}
