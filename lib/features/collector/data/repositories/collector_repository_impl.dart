import '../../../weather/domain/models/coarse_location.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/api_client.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../services/crypto/collect_key_store.dart';
import '../../../../services/crypto/commit_id.dart';
import '../../../../services/crypto/signed_transfer.dart';
import '../../../../services/crypto/station_signing.dart';
import '../../../../services/storage/local_db.dart';
import '../datasources/sensor_data_source.dart';
import '../datasources/battery_monitor.dart';
import '../models/sensor_reading_model.dart';
import '../services/sampling_policy.dart';
import '../services/station_registration_service.dart';

final collectorRepositoryProvider = Provider<CollectorRepository>((ref) {
  return CollectorRepository(
    sensorDataSource: ref.watch(sensorDataSourceProvider),
    batteryMonitor: ref.watch(batteryMonitorProvider),
    apiClient: ref.watch(apiClientProvider),
    db: kIsWeb
        ? const NoopCollectorLocalStore()
        : ref.watch(appDatabaseProvider),
  );
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'appDatabaseProvider must be overridden in ProviderScope',
  );
});

const sensorReadingsSyncTableName = 'sensor_readings';

class CollectorRepository {
  final SensorDataSource sensorDataSource;
  final BatteryMonitor batteryMonitor;
  final ApiClient apiClient;
  final CollectorLocalStore db;
  final StationRegistrationService registration;

  CollectorRepository({
    required this.sensorDataSource,
    required this.batteryMonitor,
    required this.apiClient,
    required this.db,
    StationRegistrationService? registration,
  }) : registration =
           registration ?? StationRegistrationService(apiClient: apiClient);

  /// Reads sensors and writes a reading to the local DB.
  /// Returns a typed result so the UI can distinguish device validation
  /// failures like battery throttling, missing barometer support, and
  /// location permission issues.
  Future<CollectReadingResult> collectReading({
    int batteryThreshold = 15,
    int baseIntervalMinutes = 15,
    bool force = false,
  }) async {
    final batteryLevel = await batteryMonitor.getBatteryLevel();
    if (await batteryMonitor.shouldPauseCollection(
      threshold: batteryThreshold,
    )) {
      return const CollectReadingResult.failure(
        CollectReadingFailureReason.batteryLow,
      );
    }

    final rawLocation = await sensorDataSource.readLocation();
    if (rawLocation == null) {
      return const CollectReadingResult.failure(
        CollectReadingFailureReason.locationUnavailable,
      );
    }
    // Whatever the source returned, a reading is stored and compared on the 0.1 degree grid.
    final location = (
      lat: CoarseLocation.coarsen(rawLocation.lat),
      lng: CoarseLocation.coarsen(rawLocation.lng),
    );

    final now = DateTime.now();
    if (!force) {
      final previousReading = await db.getLatestReading();
      final decision = SamplingPolicy.evaluate(
        baseIntervalMinutes: baseIntervalMinutes,
        batteryLevel: batteryLevel,
        previousReading: previousReading == null
            ? null
            : SensorReadingModel(
                id: previousReading.id,
                latitude: CoarseLocation.coarsen(previousReading.latitude),
                longitude: CoarseLocation.coarsen(previousReading.longitude),
                pressureHpa: previousReading.pressureHpa,
                timestamp: previousReading.timestamp,
                synced: previousReading.synced,
              ),
        latitude: location.lat,
        longitude: location.lng,
        now: now,
      );

      if (!decision.shouldCollect) {
        return const CollectReadingResult.failure(
          CollectReadingFailureReason.stationaryBackoff,
        );
      }
    }

    final pressure = await sensorDataSource.readBarometer();
    if (pressure == null) {
      return const CollectReadingResult.failure(
        CollectReadingFailureReason.barometerUnavailable,
      );
    }

    await db.insertReading(
      SensorReadingsCompanion.insert(
        latitude: location.lat,
        longitude: location.lng,
        pressureHpa: pressure,
        timestamp: now,
      ),
    );
    await db.upsertSyncMetadata(
      syncTableName: sensorReadingsSyncTableName,
      pendingCount: await db.getPendingSyncCount(),
      lastSyncError: null,
    );

    return CollectReadingResult.success(
      SensorReadingModel(
        latitude: location.lat,
        longitude: location.lng,
        pressureHpa: pressure,
        timestamp: now,
      ),
    );
  }

  Future<int> recommendedIntervalMinutes(int baseIntervalMinutes) async {
    final batteryLevel = await batteryMonitor.getBatteryLevel();
    return SamplingPolicy.adaptiveIntervalMinutes(
      baseIntervalMinutes: baseIntervalMinutes,
      batteryLevel: batteryLevel,
    );
  }

  /// Submits a batch of readings through the phone-signed pipeline
  /// (design §4): for each reading, `prepare`, rebuild the commit id and the
  /// commit-authorization v2 preimage LOCALLY from the prepared fields
  /// (server bytes are never signed; a disagreeing commit id aborts the
  /// batch), sign with [signer] (the phone's collect key: no biometric, so
  /// background runs can upload; the wallet key is never opened here), then
  /// submit with the phone's own station id and the auth pair.
  ///
  /// The live backend currently returns submission metadata but not a stable
  /// reward total. When a future backend response includes reward fields, this
  /// parser will surface them without inventing synthetic WRF values.
  /// [isReadingFresh] is supplied by SyncWorker at every production upload.
  /// Recheck at asynchronous boundaries, before spending a request/signature.
  Future<BatchSubmissionResult> submitBatch(
    List<SensorReading> readings, {
    required String walletAddress,
    required CommitSigner signer,
    bool includeIdempotencyKey = false,
    bool Function(SensorReading)? isReadingFresh,
  }) async {
    if (readings.isEmpty) {
      return const BatchSubmissionResult(acceptedCount: 0, failedCount: 0);
    }

    final deviceId = 'mobile:$walletAddress';
    final stationId = signer.stationId;
    final acceptedIds = <int>[];
    final alreadySubmittedIds = <int>[];
    var expiredCount = 0;
    String? lastErrorMessage;
    String? lastSubmissionId;
    String? lastCommitId;
    String? lastSubmissionStatus;
    SubmitFailure? failure;
    SubmitRefusal? refusal;
    var rewardWrfTotal = 0.0;
    var rewardTotalsAvailable = false;
    final authenticated = await apiClient.ensureWalletSession();
    if (!authenticated) {
      return BatchSubmissionResult(
        acceptedCount: 0,
        failedCount: readings.length,
        errorMessage:
            'Wallet authentication required before syncing reward readings.',
      );
    }

    for (final r in readings) {
      if (isReadingFresh != null && !isReadingFresh(r)) {
        expiredCount++;
        continue;
      }
      final timestampSeconds =
          r.timestamp.toUtc().millisecondsSinceEpoch ~/ 1000;
      // Deterministic, so a retry of the same reading commits the same id.
      final nonce = crypto.sha256
          .convert(
            utf8.encode(
              '$deviceId:${r.id}:${r.timestamp.millisecondsSinceEpoch}',
            ),
          )
          .toString()
          .substring(0, 32);
      final pressure = quantizeWeatherMeasurement(r.pressureHpa);
      final body = <String, dynamic>{
        // Backend applyDataTypeValue() only recognizes 'pressure' / 'pressure_hpa'
        // and expects `value` to be a scalar number. Sending 'barometric_pressure'
        // with an object value left pressure_hpa unset → committed as 0 (#217).
        'dataType': 'pressure_hpa',
        // 0.1 degree (~11 km) only; readings queued earlier at 3 decimals are coarsened here.
        'location': {
          'latitude': CoarseLocation.coarsen(r.latitude),
          'longitude': CoarseLocation.coarsen(r.longitude),
        },
        'value': pressure == pressure.truncateToDouble()
            ? pressure.toInt()
            : pressure,
        // deviceId/readingId are not weather fields — carry them as metadata so
        // they don't pollute the canonical reading. The backend derives the
        // wallet address from the authenticated JWT, so it is intentionally
        // omitted from the payload.
        'metadata': {'deviceId': deviceId, 'readingId': r.id},
        'timestamp': r.timestamp.toUtc().toIso8601String(),
        'source': deviceId,
        // The phone's own derived station (never the shared 'mobile-oracle').
        'stationId': stationId,
        // Prepare checks the registered collect key before the phone signs.
        'auth_pubkey': signer.publicKeyHex,
        'nonce': nonce,
        // Stable idempotency key: same reading always produces the same key
        // so the backend can reject duplicate submissions on retry.
        if (includeIdempotencyKey)
          'idempotencyKey':
              '$deviceId:${r.id}:${r.timestamp.millisecondsSinceEpoch}',
      };

      try {
        final prepared = await apiClient.dio.post(
          ApiConstants.oracleSubmitDataPrepare,
          data: body,
        );
        final localCommitId = computeCollectCommitId(
          pressureHpa: r.pressureHpa,
          nonce: nonce,
          stationId: stationId,
          timestampSeconds: timestampSeconds,
        );
        final check = _checkPrepared(
          prepared.data,
          stationId: stationId,
          nonce: nonce,
          timestampSeconds: timestampSeconds,
          localCommitId: localCommitId,
        );
        if (check != null) {
          refusal = check;
          lastErrorMessage = 'Server prepare response refused: ${check.name}';
          break;
        }
        if (isReadingFresh != null && !isReadingFresh(r)) {
          expiredCount++;
          continue;
        }
        final auth = await signer.signCommitAuthorization(
          commitId: localCommitId,
        );
        if (isReadingFresh != null && !isReadingFresh(r)) {
          expiredCount++;
          continue;
        }
        final response = await apiClient.dio.post(
          ApiConstants.oracleSubmitData,
          data: <String, dynamic>{
            ...body,
            'auth_pubkey': auth.publicKeyHex,
            'auth_signature': auth.signatureHex,
          },
        );
        if (response.data is Map &&
            _submissionAccepted(response.data as Map<dynamic, dynamic>)) {
          final payload = Map<String, dynamic>.from(
            response.data as Map<dynamic, dynamic>,
          );
          acceptedIds.add(r.id);
          lastSubmissionId = _asString(payload['submissionId']);
          lastCommitId = localCommitId;
          lastSubmissionStatus = _asString(payload['status']);

          final rewardAmount = _extractRewardWrf(payload);
          if (rewardAmount != null) {
            rewardTotalsAvailable = true;
            rewardWrfTotal += rewardAmount;
          }
        }
      } catch (error) {
        lastErrorMessage = error.toString();
        final classified = SubmitFailure.fromError(error);
        if (classified?.isAlreadySubmitted ?? false) {
          // The backend confirms this commit was already admitted. Retire
          // only this reading; no new acceptance or reward is claimed.
          alreadySubmittedIds.add(r.id);
          continue;
        }
        if (classified != null && classified.stopsBatch) {
          // Stop terminal 4xx/429 and an upstream502 before another reading
          // or an internal worker retry can replay the batch.
          failure = classified;
          break;
        }
        continue;
      }
    }

    final completedIds = [...acceptedIds, ...alreadySubmittedIds];
    if (completedIds.isNotEmpty) {
      await db.markReadingsSynced(completedIds);
      await db.upsertSyncMetadata(
        syncTableName: sensorReadingsSyncTableName,
        pendingCount: await db.getPendingSyncCount(),
        lastSyncAt: DateTime.now(),
        lastSyncError: completedIds.length == readings.length
            ? null
            : lastErrorMessage,
      );
    }

    return BatchSubmissionResult(
      acceptedCount: acceptedIds.length,
      failedCount: readings.length - completedIds.length - expiredCount,
      errorMessage: lastErrorMessage,
      lastSubmissionId: lastSubmissionId,
      lastCommitId: lastCommitId,
      lastSubmissionStatus: lastSubmissionStatus,
      rewardWrfTotal: rewardWrfTotal,
      rewardTotalsAvailable: rewardTotalsAvailable,
      failure: failure,
      refusal: refusal,
      expiredCount: expiredCount,
    );
  }

  /// Compares the server's `prepare` answer with what the phone derived
  /// itself. Null when it agrees on everything that gets signed.
  SubmitRefusal? _checkPrepared(
    Object? data, {
    required String stationId,
    required String nonce,
    required int timestampSeconds,
    required String localCommitId,
  }) {
    if (data is! Map) return SubmitRefusal.malformedPrepare;
    if (data['commitId'] != localCommitId) {
      return SubmitRefusal.commitHashMismatch;
    }
    if (data['stationId'] != stationId ||
        data['nonce'] != nonce ||
        data['timestamp'] != timestampSeconds) {
      return SubmitRefusal.authorizationMismatch;
    }
    final authorization = data['authorization'];
    if (authorization is Map) {
      if (authorization['contributionType'] != collectContributionType ||
          authorization['stationId'] != stationId ||
          authorization['commitId'] != localCommitId) {
        return SubmitRefusal.authorizationMismatch;
      }
      // The server's message bytes are only a tripwire; we sign our own.
      final serverHex = authorization['messageHex'];
      if (serverHex is String) {
        final domain = TransferSigningDomain.configured;
        final local = commitAuthorizationMessage(
          chainId: domain.chainId,
          networkId: domain.networkId,
          stationId: stationId,
          commitId: localCommitId,
          contributionType: collectContributionType,
        ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        if (serverHex != local) return SubmitRefusal.authorizationMismatch;
      }
    }
    return null;
  }

  /// Registers this phone's station with [session] (wallet) authorising
  /// [collectKey]; see [StationRegistrationService.register].
  Future<StationRegistrationResult> registerStation(
    StationSigningSession session, {
    required CollectKey collectKey,
    required double latitude,
    required double longitude,
  }) => registration.register(
    session,
    collectKey: collectKey,
    latitude: latitude,
    longitude: longitude,
  );

  /// Returns the count of unsynced readings in the local DB.
  Future<int> getUnsyncedCount() async {
    return db.getPendingSyncCount();
  }

  Future<SyncMetadataEntry?> getSyncMetadata() {
    return db.getSyncMetadata(sensorReadingsSyncTableName);
  }

  /// Returns persisted device readings in chronological order for local
  /// history features. This never falls back to live or generated samples.
  Future<List<SensorReadingModel>> getReadingHistory({int limit = 5000}) async {
    final readings = await db.getReadingHistory(limit: limit);
    return readings
        .map(
          (reading) => SensorReadingModel(
            id: reading.id,
            latitude: CoarseLocation.coarsen(reading.latitude),
            longitude: CoarseLocation.coarsen(reading.longitude),
            pressureHpa: reading.pressureHpa,
            timestamp: reading.timestamp,
            synced: reading.synced,
          ),
        )
        .toList(growable: false);
  }
}

class BatchSubmissionResult {
  final int acceptedCount;
  final int failedCount;

  /// Locally skipped by the worker's cutoff, separate from transport failures.
  /// SyncWorker retires these through its atomic durable-notice transaction.
  final int expiredCount;
  final String? errorMessage;
  final String? lastSubmissionId;

  /// core4 commit id (64 lowercase hex) of the last reading the server accepted, computed on the phone.
  final String? lastCommitId;
  final String? lastSubmissionStatus;
  final double rewardWrfTotal;
  final bool rewardTotalsAvailable;

  /// Set when the batch was stopped by a terminal 4xx,429 or upstream502.
  final SubmitFailure? failure;

  /// Set when the server's `prepare` answer disagreed with the phone's own
  /// computation; nothing was signed for that reading and the batch stopped.
  final SubmitRefusal? refusal;

  const BatchSubmissionResult({
    required this.acceptedCount,
    required this.failedCount,
    this.expiredCount = 0,
    this.errorMessage,
    this.lastSubmissionId,
    this.lastCommitId,
    this.lastSubmissionStatus,
    this.rewardWrfTotal = 0,
    this.rewardTotalsAvailable = false,
    this.failure,
    this.refusal,
  });
}

/// Why the phone refused to sign what the server prepared.
enum SubmitRefusal {
  /// The server's commit id differs from the one computed locally.
  commitHashMismatch,

  /// Station, nonce, timestamp, contribution type or message bytes differ.
  authorizationMismatch,

  /// `prepare` did not answer with a JSON object.
  malformedPrepare,
}

/// A structured HTTP failure from the oracle ingest endpoint.
class SubmitFailure {
  final int statusCode;

  /// Backend error code from the response envelope, e.g. `STATION_NOT_OWNED`.
  final String? code;

  /// Raw `Retry-After` header; resolve against a clock with [retryAfterFrom].
  final String? retryAfterHeader;

  const SubmitFailure({
    required this.statusCode,
    this.code,
    this.retryAfterHeader,
  });

  Duration? retryAfterFrom(DateTime now) =>
      parseRetryAfter(retryAfterHeader, now: now);

  bool get isRateLimited => statusCode == 429;

  /// 4xx other than 408 (timeout) and 429 (rate limit): retrying cannot help.
  bool get isTerminal =>
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 408 &&
      statusCode != 429;

  bool get stopsBatch => isTerminal || isRateLimited || statusCode == 502;

  bool get isAlreadySubmitted =>
      statusCode == 409 && code == 'COMMIT_ALREADY_SUBMITTED';

  bool get isStationNotOwned => code == 'STATION_NOT_OWNED';

  /// The commit `auth_pubkey` is not the collect key registered for the
  /// station (key lost after reinstall/restore, or rotated by a re-registration).
  bool get isCollectKeyMismatch => code == 'COLLECT_KEY_MISMATCH';

  static SubmitFailure? fromError(Object error) {
    if (error is! DioException) return null;
    final response = error.response;
    final status = response?.statusCode;
    if (response == null || status == null) return null;
    return SubmitFailure(
      statusCode: status,
      code: _errorCode(response.data),
      retryAfterHeader: response.headers.value('retry-after'),
    );
  }

  static String? _errorCode(Object? data) {
    if (data is! Map) return null;
    final error = data['error'];
    if (error is Map && error['code'] is String) return error['code'] as String;
    if (data['code'] is String) return data['code'] as String;
    if (error is String) return error;
    return null;
  }

  /// Parses `Retry-After` as delta-seconds or an HTTP date. Null when absent,
  /// unparseable, zero or negative (callers then use their default). Results
  /// are capped at [maxParsedRetryAfter] so no later arithmetic can overflow
  /// a [Duration]; the caller applies its own, tighter cap.
  static Duration? parseRetryAfter(String? raw, {required DateTime now}) {
    if (raw == null) return null;
    final value = raw.trim();
    final seconds = int.tryParse(value);
    if (seconds != null) {
      if (seconds <= 0) return null;
      if (seconds >= maxParsedRetryAfter.inSeconds) return maxParsedRetryAfter;
      return Duration(seconds: seconds);
    }
    if (RegExp(r'^[+-]?\d+$').hasMatch(value)) {
      // Digits only but beyond int64: negative -> invalid, else clamp.
      return value.startsWith('-') ? null : maxParsedRetryAfter;
    }
    final date = _parseHttpDate(value);
    if (date == null) return null;
    final delta = date.difference(now);
    if (delta <= Duration.zero) return null;
    return delta > maxParsedRetryAfter ? maxParsedRetryAfter : delta;
  }

  static const Duration maxParsedRetryAfter = Duration(days: 365);

  static const _months = <String>[
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec', //
  ];

  // IMF-fixdate: "Tue, 29 Sep 2026 12:05:00 GMT".
  static DateTime? _parseHttpDate(String value) {
    final m = RegExp(
      r'^[A-Za-z]{3},\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
      r'(\d{2}):(\d{2}):(\d{2})\s+GMT$',
    ).firstMatch(value);
    if (m == null) return null;
    final month = _months.indexOf(m.group(2)!.toLowerCase());
    if (month < 0) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month + 1,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}

abstract class CollectorLocalStore {
  Future<int> insertReading(SensorReadingsCompanion reading);

  Future<SensorReading?> getLatestReading();

  Future<List<SensorReading>> getReadingHistory({int limit = 5000}) async {
    final latest = await getLatestReading();
    return latest == null ? const [] : [latest];
  }

  Future<void> markReadingsSynced(List<int> ids);

  Future<int> getPendingSyncCount();

  Future<void> clearUnsyncedReadings();

  Future<void> clearPendingImages();

  Future<void> clearSyncMetadata(String syncTableName);

  Future<SyncMetadataEntry?> getSyncMetadata(String syncTableName);

  Future<void> upsertSyncMetadata({
    required String syncTableName,
    required int pendingCount,
    DateTime? lastSyncAt,
    DateTime? lastSyncAttemptAt,
    String? lastSyncError,
  });
}

class NoopCollectorLocalStore implements CollectorLocalStore {
  const NoopCollectorLocalStore();

  @override
  Future<void> clearPendingImages() async {}

  @override
  Future<void> clearSyncMetadata(String syncTableName) async {}

  @override
  Future<void> clearUnsyncedReadings() async {}

  @override
  Future<SyncMetadataEntry?> getSyncMetadata(String syncTableName) async =>
      null;

  @override
  Future<int> getPendingSyncCount() async => 0;

  @override
  Future<int> insertReading(SensorReadingsCompanion reading) async => 0;

  @override
  Future<SensorReading?> getLatestReading() async => null;

  @override
  Future<List<SensorReading>> getReadingHistory({int limit = 5000}) async =>
      const [];

  @override
  Future<void> markReadingsSynced(List<int> ids) async {}

  @override
  Future<void> upsertSyncMetadata({
    required String syncTableName,
    required int pendingCount,
    DateTime? lastSyncAt,
    DateTime? lastSyncAttemptAt,
    String? lastSyncError,
  }) async {}
}

enum CollectReadingFailureReason {
  batteryLow,
  barometerUnavailable,
  locationUnavailable,
  stationaryBackoff,
}

class CollectReadingResult {
  final SensorReadingModel? reading;
  final CollectReadingFailureReason? failureReason;

  const CollectReadingResult.success(this.reading) : failureReason = null;

  const CollectReadingResult.failure(this.failureReason) : reading = null;

  bool get isSuccess => reading != null;
}

bool _submissionAccepted(Map<dynamic, dynamic> payload) {
  return payload['success'] == true || payload['accepted'] == true;
}

String? _asString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? _extractRewardWrf(Map<String, dynamic> payload) {
  for (final key in const [
    'rewardAmount',
    'rewardTotal',
    'earnedWrf',
    'wrfEarned',
    'totalReward',
  ]) {
    final parsed = _parseDouble(payload[key]);
    if (parsed != null) return parsed;
  }

  final rewards = payload['rewards'];
  if (rewards is Map) {
    final parsed = _parseDouble(rewards['totalAmount'] ?? rewards['amount']);
    if (parsed != null) return parsed;
  }

  return null;
}

double? _parseDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
