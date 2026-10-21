import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/crypto/collect_key_store.dart';
import '../../../../services/crypto/signed_transfer.dart';
import '../../../../services/crypto/station_signing.dart';
import '../repositories/collector_repository_impl.dart' show SubmitFailure;

/// Why a registration attempt produced no registered station.
enum RegistrationProblem {
  /// The server challenge named another station, owner or chain: not signed.
  challengeMismatch,

  /// The server answered with a station id that is not the derived one.
  stationIdMismatch,

  /// The server answered with an unusable body.
  malformedResponse,

  /// An HTTP failure (see [StationRegistrationResult.failure]) or no response.
  requestFailed,
}

class StationRegistrationResult {
  const StationRegistrationResult.registered(this.stationId)
    : problem = null,
      failure = null;
  const StationRegistrationResult.failed(this.problem, {this.failure})
    : stationId = null;

  final String? stationId;
  final RegistrationProblem? problem;
  final SubmitFailure? failure;

  bool get ok => problem == null;
}

/// Registers this wallet's own per-phone station (design §3.2, M3):
/// challenge -> verify it names *our* derived id / owner / chain -> sign
/// preimages A v2 (naming the collect key) and B with the caller's one
/// wallet signing session -> register. Re-registering with a new collect key
/// replaces the old one on the backend.
/// The registered cell is the 0.1 degree cell (ruling Q3); the exact
/// coordinates never leave the phone here.
class StationRegistrationService {
  StationRegistrationService({
    required this.apiClient,
    this._domain = TransferSigningDomain.configured,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// SharedPreferences key holding `<stationId>:<collectPubkey>` last confirmed
  /// registered (v2). The old M3 key (`mobile_station_registered_id`, a bare
  /// station id under the wallet-signs-commits scheme) is never read: an
  /// install that registered under v1 has no collect key on the backend, so it
  /// counts as unregistered and re-registers on its next foreground sync.
  static const registeredStationKey = 'mobile_station_registered_v2';

  static String registrationMarker(String stationId, String collectPubkey) =>
      '$stationId:${collectPubkey.toLowerCase()}';

  /// A server challenge is at most 5 minutes (design §3.3); refuse anything
  /// far beyond that rather than sign an open-ended expiry.
  static const maxChallengeLifetime = Duration(minutes: 10);

  final ApiClient apiClient;
  final TransferSigningDomain _domain;
  final DateTime Function() _now;

  /// True when this station was registered WITH this collect key.
  Future<bool> isRegistered(String stationId, String collectPubkey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // The foreground app and the Workmanager isolate share this value.
      await prefs.reload();
      return prefs.getString(registeredStationKey) ==
          registrationMarker(stationId, collectPubkey);
    } catch (_) {
      return false;
    }
  }

  Future<void> forget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(registeredStationKey);
    } catch (_) {}
  }

  Future<void> _remember(String stationId, String collectPubkey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        registeredStationKey,
        registrationMarker(stationId, collectPubkey),
      );
    } catch (_) {}
  }

  /// Rounds a coordinate to integer tenths of a degree, clamped to the grid.
  static int cellE1(double degrees, {required int limit}) =>
      (degrees * 10).round().clamp(-limit, limit);

  Future<StationRegistrationResult> register(
    StationSigningSession session, {
    required CollectKey collectKey,
    required double latitude,
    required double longitude,
  }) async {
    final stationId = session.stationId;
    try {
      final challengeResponse = await apiClient.dio.post<dynamic>(
        ApiConstants.mobileStationChallenge,
      );
      final challenge = challengeResponse.data;
      if (challenge is! Map) {
        return const StationRegistrationResult.failed(
          RegistrationProblem.malformedResponse,
        );
      }
      final nonce = challenge['nonce'];
      final expiresAt = challenge['expiresAt'];
      if (nonce is! String || expiresAt is! int) {
        return const StationRegistrationResult.failed(
          RegistrationProblem.malformedResponse,
        );
      }
      // Never sign a challenge that is not about us (design §3.2).
      final nowSeconds = _now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (challenge['stationId'] != stationId ||
          (challenge['ownerAddress'] as String?)?.toLowerCase() !=
              session.ownerAddress ||
          challenge['chainId'] != _domain.chainId ||
          challenge['networkId'] != _domain.networkId ||
          expiresAt <= nowSeconds ||
          expiresAt > nowSeconds + maxChallengeLifetime.inSeconds) {
        return const StationRegistrationResult.failed(
          RegistrationProblem.challengeMismatch,
        );
      }

      final latE1 = cellE1(latitude, limit: 900);
      final lonE1 = cellE1(longitude, limit: 1800);
      final collectPubkey = collectKey.publicKeyHex;
      final registration = await session.signRegistration(
        collectPubkey: collectPubkey,
        latE1: latE1,
        lonE1: lonE1,
        nonce: nonce,
        expiresAt: expiresAt,
      );
      final ownership = await session.signOwnership();

      final response = await apiClient.dio.post<dynamic>(
        ApiConstants.mobileStationRegister,
        data: <String, dynamic>{
          'version': 2,
          'nonce': nonce,
          'expiresAt': expiresAt,
          'publicKey': registration.publicKeyHex,
          'collectPubkey': collectPubkey,
          'registrationSignature': registration.signatureHex,
          'ownershipSignature': ownership.signatureHex,
          'cell': <String, int>{'latE1': latE1, 'lonE1': lonE1},
          'deviceClass': 'phone-barometer',
        },
      );
      final data = response.data;
      if (data is! Map || data['stationId'] is! String) {
        return const StationRegistrationResult.failed(
          RegistrationProblem.malformedResponse,
        );
      }
      if (data['stationId'] != stationId) {
        return const StationRegistrationResult.failed(
          RegistrationProblem.stationIdMismatch,
        );
      }
      await _remember(stationId, collectPubkey);
      return StationRegistrationResult.registered(stationId);
    } on DioException catch (error) {
      return StationRegistrationResult.failed(
        RegistrationProblem.requestFailed,
        failure: SubmitFailure.fromError(error),
      );
    }
  }
}
