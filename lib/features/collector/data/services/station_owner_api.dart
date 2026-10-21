import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/station_owner_models.dart';

// Transport for station owner actions (spec rev e14b961; backend relay
// feat/station-owner-actions-relay). The phone NEVER calls the node: it talks
// to the backend relay, addressing the station by its public ALIAS.

/// `st_` + first 12 hex of sha256("wrfcoin-station-alias-v1:" + stationId),
/// byte-identical to backend `stationAlias`.
String stationAliasOf(String stationId) {
  final digest = crypto.sha256.convert(
    utf8.encode('wrfcoin-station-alias-v1:$stationId'),
  );
  return 'st_${digest.toString().substring(0, 12)}';
}

class StationOwnerPaths {
  const StationOwnerPaths._();

  /// `POST /stations/{alias}/owner-actions`, body `{kind, payload}`.
  static String submit(String alias) => '/stations/$alias/owner-actions';

  /// `GET /stations/{alias}/ownership`: the owner-ledger fields (spec §7.2).
  static String ledger(String alias) => '/stations/$alias/ownership';
}

/// Stable machine codes from the node (switch on `error.code`, never on the
/// human message).
enum StationOwnerRefusal {
  featureNotActive('OWNER_TX_FEATURE_NOT_ACTIVE'),
  malformed('OWNER_TX_MALFORMED'),
  sameOwner('OWNER_TX_SAME_OWNER'),
  fromKeyNotBound('OWNER_TX_FROM_KEY_NOT_BOUND'),
  toKeyNotBound('OWNER_TX_TO_KEY_NOT_BOUND'),
  ownerKeyNotBound('OWNER_TX_OWNER_KEY_NOT_BOUND'),
  badOwnerSignature('OWNER_TX_BAD_OWNER_SIGNATURE'),
  badCountersignature('OWNER_TX_BAD_COUNTERSIGNATURE'),
  expired('OWNER_TX_EXPIRED'),
  validityTooLong('OWNER_TX_VALIDITY_TOO_LONG'),
  unknownStation('OWNER_TX_UNKNOWN_STATION'),
  notRegisteredOwner('OWNER_TX_NOT_REGISTERED_OWNER'),
  nonceMismatch('OWNER_TX_NONCE_MISMATCH'),
  nonceExhausted('OWNER_TX_NONCE_EXHAUSTED'),
  stationFrozen('OWNER_TX_STATION_FROZEN'),
  notFrozen('OWNER_TX_NOT_FROZEN'),
  alreadyDeactivated('OWNER_TX_ALREADY_DEACTIVATED'),
  notDeactivated('OWNER_TX_NOT_DEACTIVATED'),
  recoveryAlreadyPending('OWNER_TX_RECOVERY_ALREADY_PENDING'),
  noPendingRecovery('OWNER_TX_NO_PENDING_RECOVERY'),
  noticeWindowElapsed('OWNER_TX_NOTICE_WINDOW_ELAPSED'),
  noticeWindowNotElapsed('OWNER_TX_NOTICE_WINDOW_NOT_ELAPSED'),
  duplicateStationInBatch('OWNER_TX_DUPLICATE_STATION_IN_BATCH'),
  staleTimestamp('OWNER_TX_STALE_TIMESTAMP'),
  idMismatch('OWNER_TX_ID_MISMATCH'),
  idMissing('OWNER_TX_ID_MISSING'),
  chainIdentityMismatch('CHAIN_IDENTITY_MISMATCH'),
  mempoolRejected('MEMPOOL_REJECTED'),
  timestampWindow('TIMESTAMP_WINDOW'),

  /// A 2xx whose body is not the exact pending shape: we cannot tell whether
  /// the network accepted it. NEVER read as "not accepted".
  uncertain('UNCERTAIN_RESPONSE'),
  invalidOwnerAction('INVALID_OWNER_ACTION'),
  loginRequired('WALLET_LOGIN_REQUIRED'),
  notTheSigner('NOT_THE_SIGNER'),
  rateLimited('RATE_LIMITED'),
  stationNotFound('STATION_NOT_FOUND'),
  stationNotRegistered('STATION_NOT_REGISTERED'),
  notOffered('RECOVERY_FILE_NOT_OFFERED'),

  /// 503: the relay or node could not answer. NEVER read this as "no".
  unavailable('RELAY_UNAVAILABLE'),
  unknown('');

  const StationOwnerRefusal(this.code);
  final String code;

  static StationOwnerRefusal fromCode(Object? code) {
    if (code is! String) return unknown;
    // No standalone recovery accept exists on the relay.
    if (code == 'UNSUPPORTED_KIND') return notOffered;
    for (final r in values) {
      if (r.code.isNotEmpty && r.code == code) return r;
    }
    return unknown;
  }

  /// Fixed user-facing text. Server messages are never shown.
  String get userMessage => switch (this) {
    featureNotActive =>
      'Station ownership changes are not active on the network yet.',
    expired || validityTooLong =>
      'This request has expired. Ask for a fresh one and try again.',
    nonceMismatch =>
      'The station changed since this request was made. Start again.',
    notRegisteredOwner => 'The sender is no longer the owner of this station.',
    stationFrozen =>
      'This station is frozen. Unfreeze it before changing ownership.',
    badOwnerSignature ||
    badCountersignature ||
    fromKeyNotBound ||
    toKeyNotBound ||
    ownerKeyNotBound => 'The signatures on this request were not accepted.',
    unknownStation => 'The network does not know this station.',
    noPendingRecovery => 'There is no recovery pending for this station.',
    noticeWindowElapsed => 'The window to cancel this recovery has closed.',
    noticeWindowNotElapsed =>
      'This recovery cannot be completed until its waiting period ends.',
    recoveryAlreadyPending => 'A recovery is already pending for this station.',
    staleTimestamp ||
    timestampWindow => 'Your phone clock looks wrong. Check it and try again.',
    loginRequired => 'Sign in with the wallet that owns this station.',
    notTheSigner => 'This wallet is not a party to this request.',
    rateLimited => 'Too many requests. Wait a moment and try again.',
    stationNotFound => 'The network does not know this station.',
    stationNotRegistered =>
      'This station is not registered on the network yet.',
    notOffered => 'This action is not available from the app.',
    unavailable => 'Station ownership is unavailable right now. Nothing was changed. Try again.',
    uncertain =>
      'We could not tell whether the network accepted this. Check the '
          'station status before trying again.',
    _ => 'The network did not accept this request.',
  };
}

class StationOwnerException implements Exception {
  const StationOwnerException(this.refusal, {this.code, this.network = false});

  final StationOwnerRefusal refusal;

  /// Raw machine code as received, for logs and tests (never a message).
  final String? code;

  /// True when the failure was transport (no response), not a refusal.
  final bool network;

  @override
  String toString() => 'StationOwnerException(${code ?? refusal.name})';
}

/// A signed owner payload for the relay: the client `kind` (`transfer`,
/// `owner_action`, `recovery_cancel`, `recovery_execute`) and the signed
/// payload JSON string (`tx.data`). The NODE builds the transaction envelope;
/// the relay forwards the payload untouched.
@immutable
class SignedOwnerPayload {
  const SignedOwnerPayload({
    required this.stationId,
    required this.kind,
    required this.payload,
  });
  final String stationId;
  final String kind;
  final String payload;
}

/// A 201 is `{status: 'accepted_pending_confirmation', ...}`: ACCEPTED, not
/// applied. Never show success from it.
@immutable
class OwnerSubmitReceipt {
  const OwnerSubmitReceipt({
    required this.transactionIds,
    required this.admissionHeight,
  });
  final List<String> transactionIds;
  final int? admissionHeight;
}

abstract class StationOwnerApi {
  Future<OwnerLedger> readLedger(String stationId);
  Future<OwnerSubmitReceipt> submit(SignedOwnerPayload tx);
}

class DioStationOwnerApi implements StationOwnerApi {
  DioStationOwnerApi(this._dio);

  final Dio _dio;

  static StationOwnerException _fail(DioException e) {
    final res = e.response;
    if (res == null) {
      return const StationOwnerException(
        StationOwnerRefusal.unknown,
        network: true,
      );
    }
    final data = res.data;
    final err = data is Map ? data['error'] : null;
    final code = err is Map ? err['code'] : null;
    var refusal = StationOwnerRefusal.fromCode(code);
    if (refusal == StationOwnerRefusal.unknown) {
      // Status fallback. 503 is "unavailable", never an answer.
      refusal = switch (res.statusCode) {
        final c? when c >= 500 => StationOwnerRefusal.unavailable,
        401 => StationOwnerRefusal.loginRequired,
        403 => StationOwnerRefusal.notTheSigner,
        429 => StationOwnerRefusal.rateLimited,
        _ => StationOwnerRefusal.unknown,
      };
    }
    return StationOwnerException(refusal, code: code is String ? code : null);
  }

  @override
  Future<OwnerLedger> readLedger(String stationId) async {
    try {
      final r = await _dio.get<dynamic>(
        StationOwnerPaths.ledger(stationAliasOf(stationId)),
      );
      return OwnerLedger.fromJson(r.data);
    } on DioException catch (e) {
      throw _fail(e);
    } on FormatException {
      // A 200 that is not the expected shape is a contract mismatch: the
      // state is unavailable, never defaulted to "not frozen".
      throw const StationOwnerException(StationOwnerRefusal.unavailable);
    }
  }

  @override
  Future<OwnerSubmitReceipt> submit(SignedOwnerPayload tx) async {
    try {
      // The relay forwards the source text of the top-level `payload` value
      // byte for byte, so the body is assembled by hand: the signed text is
      // embedded as-is and never re-encoded.
      final r = await _dio.post<dynamic>(
        StationOwnerPaths.submit(stationAliasOf(tx.stationId)),
        data: '{"kind":${jsonEncode(tx.kind)},"payload":${tx.payload}}',
        options: Options(contentType: Headers.jsonContentType),
      );
      final d = r.data;
      final ids = d is Map ? d['transactionIds'] : null;
      final h = d is Map ? d['admissionHeight'] : null;
      if (d is! Map ||
          d['status'] != 'accepted_pending_confirmation' ||
          d['applied'] != false ||
          ids is! List ||
          (h != null && h is! int)) {
        // Something answered 2xx: do not claim a refusal and invite a resend.
        throw const StationOwnerException(StationOwnerRefusal.uncertain);
      }
      return OwnerSubmitReceipt(
        transactionIds: ids.map((e) => e.toString()).toList(),
        admissionHeight: h as int?,
      );
    } on DioException catch (e) {
      throw _fail(e);
    }
  }
}
