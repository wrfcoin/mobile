import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/collector/data/datasources/battery_monitor.dart';
import '../../features/collector/data/datasources/sensor_data_source.dart';
import '../../features/collector/data/repositories/collector_repository_impl.dart';
import '../../features/collector/data/services/station_registration_service.dart';
import '../../features/collector/data/services/mobile_station_status_service.dart';
import '../../services/api/api_client.dart';
import '../../services/auth/biometric_service.dart';
import '../../services/crypto/collect_key_store.dart';
import '../../services/crypto/key_manager.dart';
import '../../services/crypto/station_signing.dart';
import '../../services/crypto/wallet_secure_storage.dart';
import '../../services/location/location_service.dart';
import '../storage/db_path_stub.dart'
    if (dart.library.io) '../storage/db_path.dart';
import '../storage/local_db.dart';

class SyncWorker {
  static const int maxBatchSize = 50;
  static const int maxRetries = 5;

  /// Used when a 429 carries no usable `Retry-After`.
  static const Duration defaultRateLimitBackoff = Duration(minutes: 15);

  /// Upper bound on any rate-limit lock (Retry-After or persisted).
  static const Duration maxRateLimitBackoff = Duration(hours: 1);

  static const String nextAllowedAtKey = 'sync_next_allowed_at_ms';

  /// The oracle attester refuses readings older than 3600 s at evaluation
  /// (core4 `shared-protocol/src/oracle/mechanical.rs:53,223`
  /// `DEFAULT_MAX_AGE_SECS`; infra `testnet/docker-compose.oracle-attester.yml:148`
  /// `WRFCOIN_ATTESTER_MAX_AGE_SECS`). A reading past that earns nothing yet
  /// still spends two requests and a slice of the per-station commit cap, so
  /// it is dropped instead of signed. 50 minutes leaves ~10 for mempool dwell
  /// and attester delay.
  static const Duration maxReadingAge = Duration(minutes: 50);

  static const String earningWindowMessage =
      'Saved readings can upload for 50 minutes. Attester approval normally '
      'needs to happen within about one hour of capture. Offline storage and '
      'upload acceptance do not guarantee rewards.';

  static String staleReadingsNotice(int count) =>
      '$count saved ${count == 1 ? 'reading was' : 'readings were'} unable '
      'to earn rewards and ${count == 1 ? 'was' : 'were'} removed.';

  static String registrationNeededMessage(int count) =>
      '$count ${count == 1 ? 'reading is' : 'readings are'} waiting — '
      'open the app to register your weather station.';

  static String reRegistrationNeededMessage(int count) =>
      '$count ${count == 1 ? 'reading is' : 'readings are'} waiting — '
      'open the app to re-register your weather station.';

  static const String signingRefusedMessage =
      'Upload needs your fingerprint or PIN. Readings are saved; try again '
      'from the app.';

  static const String signingUnavailableMessage =
      'This wallet cannot sign uploads. Readings are saved.';

  static const String registrationRefusedMessage =
      "The server's station registration did not match your wallet, so it "
      'was not used. Readings are saved.';

  static const String commitRefusedMessage =
      "The server's upload details did not match what your phone computed, "
      'so nothing was signed. Readings are saved.';

  static const String stationNotRegisteredMessage =
      'Station ownership was rejected. This run stopped; readings are saved. '
      'Register your station from the app before the next sync.';

  final Connectivity _connectivity;
  final WalletSecureStorage _walletSecureStorage;
  final AppDatabase Function() _dbFactory;
  final CollectorRepository Function(AppDatabase) _repositoryFactory;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;

  /// Opens the wallet signing session (one biometric prompt) used ONLY to
  /// register the station and authorise its collect key. Null in the
  /// Workmanager isolate: background runs never open the wallet key. Commits
  /// are signed by the collect key, which needs no session (design §11).
  final Future<StationSigningSession?> Function()? _sessionOpener;

  final CollectKeyStore _collectKeys;

  SyncWorker({
    Connectivity? connectivity,
    WalletSecureStorage? walletSecureStorage,
    AppDatabase Function()? dbFactory,
    CollectorRepository Function(AppDatabase)? repositoryFactory,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
    Future<StationSigningSession?> Function()? sessionOpener,
    CollectKeyStore? collectKeyStore,
    // False in the Workmanager isolate: it may use or refresh a session but
    // never starts a wallet login (mobile#313).
    bool canStartLogin = true,
  }) : _connectivity = connectivity ?? Connectivity(),
       _walletSecureStorage =
           walletSecureStorage ?? const WalletSecureStorage(),
       _dbFactory = dbFactory ?? (() => AppDatabase(openAppDatabase())),
       _repositoryFactory =
           repositoryFactory ??
           ((db) => _createRepository(db, canStartLogin: canStartLogin)),
       _delay = delay ?? Future.delayed,
       _now = now ?? DateTime.now,
       _collectKeys = collectKeyStore ?? CollectKeyStore(),
       // A background worker never signs, whatever opener it is handed.
       _sessionOpener = canStartLogin
           ? (sessionOpener ?? _openWalletSession)
           : null;

  static Future<StationSigningSession?> _openWalletSession() =>
      StationSigningService(
        keyManager: KeyManager(biometric: BiometricService()),
      ).openSession();

  Future<bool> hasConnection() async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;

  static CollectorRepository _createRepository(
    AppDatabase db, {
    required bool canStartLogin,
  }) {
    return CollectorRepository(
      sensorDataSource: SensorDataSource(LocationService()),
      batteryMonitor: BatteryMonitor(),
      apiClient: ApiClient(
        keyManager: KeyManager(biometric: BiometricService()),
        canStartLogin: canStartLogin,
      ),
      db: db,
    );
  }

  Future<SyncRunResult> syncPendingReadings({
    bool includeIdempotencyKey = false,
  }) => _syncPendingReadings(includeIdempotencyKey: includeIdempotencyKey);

  /// Resume checks activation even for an empty queue. It never opens the
  /// wallet signer or registers a station; registration stays user initiated.
  Future<SyncRunResult> syncOnResume({bool includeIdempotencyKey = false}) =>
      _syncPendingReadings(
        includeIdempotencyKey: includeIdempotencyKey,
        checkWhenIdle: true,
      );

  Future<SyncRunResult> _syncPendingReadings({
    required bool includeIdempotencyKey,
    bool checkWhenIdle = false,
  }) async {
    final attemptedAt = _now();
    final db = _dbFactory();

    try {
      final pendingBefore = await db.getPendingSyncCount();

      if (pendingBefore == 0 && !checkWhenIdle) {
        await _writeMetadata(
          db,
          pendingCount: 0,
          lastSyncAttemptAt: attemptedAt,
          lastSyncError: null,
        );
        return await _buildResult(
          db,
          acceptedCount: 0,
          failedCount: 0,
          pendingCount: 0,
          message: null,
          reason: SyncRunReason.idle,
        );
      }

      // Expiry is local housekeeping, even while offline or rate limited.
      // The existing transaction keeps deletion and its durable notice atomic.
      var droppedStale = pendingBefore == 0
          ? 0
          : await db.dropStaleReadingsWithNotice(
              _now().subtract(maxReadingAge),
            );
      var notice = droppedStale > 0 ? staleReadingsNotice(droppedStale) : null;
      var pendingNow = droppedStale == 0
          ? pendingBefore
          : await db.getPendingSyncCount();
      if (pendingNow == 0 && !checkWhenIdle) {
        await _writeMetadata(
          db,
          pendingCount: 0,
          lastSyncAttemptAt: attemptedAt,
          lastSyncError: null,
        );
        return await _buildResult(
          db,
          acceptedCount: 0,
          failedCount: 0,
          pendingCount: 0,
          message: null,
          reason: SyncRunReason.idle,
          droppedStaleCount: droppedStale,
          notice: notice,
        );
      }

      if (!await hasConnection()) {
        const message = 'Offline. Waiting for connection.';
        await _writeMetadata(
          db,
          pendingCount: pendingNow,
          lastSyncAttemptAt: attemptedAt,
          lastSyncError: message,
        );
        return await _buildResult(
          db,
          acceptedCount: 0,
          failedCount: 0,
          pendingCount: pendingNow,
          message: message,
          reason: SyncRunReason.offline,
          droppedStaleCount: droppedStale,
          notice: notice,
        );
      }

      final walletAddress = await _walletSecureStorage.getWalletAddress();
      if (walletAddress == null) {
        const message = 'Create a wallet before syncing collected data.';
        await _writeMetadata(
          db,
          pendingCount: pendingNow,
          lastSyncAttemptAt: attemptedAt,
          lastSyncError: message,
        );
        return await _buildResult(
          db,
          acceptedCount: 0,
          failedCount: 0,
          pendingCount: pendingNow,
          message: message,
          reason: SyncRunReason.walletMissing,
          droppedStaleCount: droppedStale,
          notice: notice,
        );
      }

      final blockedUntil = await _rateLimitedUntil();
      if (blockedUntil != null) {
        await _writeMetadata(
          db,
          pendingCount: pendingNow,
          lastSyncAttemptAt: attemptedAt,
          lastSyncError: rateLimitedMessage,
        );
        return await _buildResult(
          db,
          acceptedCount: 0,
          failedCount: 0,
          pendingCount: pendingNow,
          message: rateLimitedMessage,
          reason: SyncRunReason.rateLimited,
          retryAfterUntil: blockedUntil,
          droppedStaleCount: droppedStale,
          notice: notice,
        );
      }

      final openSession = checkWhenIdle ? null : _sessionOpener;

      final owner = walletAddress.trim().toLowerCase();
      final String stationId;
      try {
        stationId = deriveMobileStationId(owner);
      } on ArgumentError {
        const message = signingUnavailableMessage;
        await _writeMetadata(
          db,
          pendingCount: pendingNow,
          lastSyncAttemptAt: attemptedAt,
          lastSyncError: message,
        );
        return await _buildResult(
          db,
          acceptedCount: 0,
          failedCount: 0,
          pendingCount: pendingNow,
          message: message,
          reason: SyncRunReason.signingUnavailable,
          droppedStaleCount: droppedStale,
          notice: notice,
        );
      }

      // Construct the repository only once the guards have passed — the real
      // factory wires ApiClient/KeyManager/Biometric and should not run on
      // idle/offline/wallet-missing short-circuits.
      final repository = _repositoryFactory(db);

      // The collect key: read without any prompt, so this works in the
      // Workmanager isolate. Null on first run, after a reinstall/restore, or
      // when it belongs to another wallet.
      var collectKey = await _collectKeys.load(owner);

      var acceptedCount = 0;
      var failedCount = 0;
      String? lastError;
      var failures = 0;
      String? lastSubmissionId;
      String? lastSubmissionStatus;
      var rewardWrfTotal = 0.0;
      var rewardTotalsAvailable = false;
      var reason = SyncRunReason.success;
      int? rejectedStatus;
      String? rejectedCode;
      DateTime? retryAfterUntil;
      var reRegistered = false;

      Future<void> discardBeforeActivationCheck() async {
        droppedStale += await db.dropUnactivatedReadingsWithNotice();
        notice = droppedStale > 0 ? staleReadingsNotice(droppedStale) : null;
        pendingNow = await db.getPendingSyncCount();
      }

      Future<bool> checkActivation({MobileStationStatus? known}) async {
        final status =
            known ??
            await MobileStationStatusService(
              apiClient: repository.apiClient,
              db: db,
            ).fetch(owner);
        final holdKey = 'mobile_station_activation_hold:$stationId';
        if (status.cached || status.phase != MobileStationPhase.onChain) {
          // Durable and station-bound: survives process/background restarts.
          await db.upsertOfflineData(holdKey, 'awaiting');
          if (!status.cached &&
              (status.phase == MobileStationPhase.dbOnly ||
                  status.phase == MobileStationPhase.submitted)) {
            await discardBeforeActivationCheck();
            reason = SyncRunReason.awaitingActivation;
            lastError = MobileStationStatus.awaitingActivationMessage;
          } else {
            reason = SyncRunReason.activationUnknown;
            lastError = status.message;
          }
          return false;
        }
        if (await db.getOfflineData(holdKey) != null) {
          // No activation time in the API: only readings collected AFTER the
          // first confirmed activation can safely enter the upload path.
          await db.transaction(() async {
            await discardBeforeActivationCheck();
            await db.deleteOfflineData(holdKey);
          });
        }
        return true;
      }

      // Applies a terminal 4xx / 429 to the run outcome (never retried).
      Future<void> applyStop(SubmitFailure terminal) async {
        if (terminal.statusCode == 409 &&
            terminal.code == 'STATION_NOT_ACTIVE') {
          await db.upsertOfflineData(
            'mobile_station_activation_hold:$stationId',
            'awaiting',
          );
          await discardBeforeActivationCheck();
          reason = SyncRunReason.awaitingActivation;
          lastError = MobileStationStatus.awaitingActivationMessage;
          failedCount = 0;
        } else if (terminal.isRateLimited) {
          final now = _now();
          var delay = terminal.retryAfterFrom(now) ?? defaultRateLimitBackoff;
          if (delay > maxRateLimitBackoff) delay = maxRateLimitBackoff;
          retryAfterUntil = now.add(delay);
          await _setNextAllowed(retryAfterUntil!);
          reason = SyncRunReason.rateLimited;
          lastError = rateLimitedMessage;
        } else if (terminal.statusCode == 502) {
          reason = SyncRunReason.failure;
          lastError = 'The server could not complete this upload. This run stopped; readings are saved.';
        } else if (terminal.isStationNotOwned) {
          reason = SyncRunReason.stationNotRegistered;
          lastError = stationNotRegisteredMessage;
        } else {
          reason = SyncRunReason.rejected;
          rejectedStatus = terminal.statusCode;
          rejectedCode = terminal.code;
          lastError = switch (terminal.statusCode) {
            401 => 'Session expired. Sign in again from the wallet, then retry Collect. Readings are saved.',
            409 when terminal.code == 'STATION_ID_TAKEN' => 'This station id belongs to another owner. Registration stopped; report this error. Readings are saved.',
            400 || 422 => 'Station or reading validation failed. This run stopped; readings are saved.',
            _ =>
              'The server rejected the readings (HTTP ${terminal.statusCode}). This run stopped; readings are saved.',
          };
        }
      }

      // Registers this phone's station and authorises its collect key: the
      // ONLY use of the wallet key, foreground only, one biometric prompt,
      // closed straight after. The cell comes from the most recent queued
      // reading, rounded to 0.1 degree inside the registration service.
      // [freshKey] replaces the collect key (lost / rotated out). Returns
      // false after recording why not.
      Future<bool> registerStation({
        bool freshKey = false,
        bool rotation = false,
      }) async {
        final opener = openSession;
        if (opener == null) {
          reason = SyncRunReason.awaitingForeground;
          lastError = rotation
              ? reRegistrationNeededMessage(pendingNow)
              : registrationNeededMessage(pendingNow);
          return false;
        }
        final latest = await db.getLatestUnsyncedReading();
        if (latest == null) return true;
        StationSigningSession? session;
        try {
          try {
            session = await opener();
          } on StationSigningForegroundRequired {
            reason = SyncRunReason.awaitingForeground;
            lastError = registrationNeededMessage(pendingNow);
            return false;
          } on StationSigningUnavailable {
            reason = SyncRunReason.signingUnavailable;
            lastError = signingUnavailableMessage;
            return false;
          }
          if (session == null) {
            // Refused prompt: nothing was sent, and we do not prompt again.
            reason = SyncRunReason.signingRefused;
            lastError = signingRefusedMessage;
            return false;
          }
          final CollectKey key;
          try {
            key = freshKey
                ? await _collectKeys.createFresh(owner)
                : (collectKey ?? await _collectKeys.createFresh(owner));
          } catch (_) {
            reason = SyncRunReason.signingUnavailable;
            lastError =
                'Collect key storage is unavailable. '
                'Readings are saved; try again from the app later.';
            return false;
          }
          final outcome = await repository.registerStation(
            session,
            collectKey: key,
            latitude: latest.latitude,
            longitude: latest.longitude,
          );
          if (outcome.ok) {
            collectKey = key;
            return true;
          }
          final why = outcome.failure;
          if (why != null && why.stopsBatch) {
            await applyStop(why);
          } else if (outcome.problem == RegistrationProblem.requestFailed) {
            reason = SyncRunReason.failure;
            lastError =
                'Could not register your weather station. '
                'Readings are saved and will upload later.';
          } else {
            reason = SyncRunReason.registrationRefused;
            lastError = registrationRefusedMessage;
          }
          return false;
        } finally {
          // The wallet signer lives in memory only for the registration.
          session?.close();
        }
      }

      var proceed = true;
      final existing = collectKey;
      if (checkWhenIdle) proceed = await checkActivation();
      var locallyRegistered =
          existing != null &&
          await repository.registration.isRegistered(
            stationId,
            existing.publicKeyHex,
          );
      MobileStationStatus? known;
      if (proceed &&
          !checkWhenIdle &&
          openSession != null &&
          pendingNow > 0 &&
          locallyRegistered) {
        // A backend or chain reset forgets every registration while this
        // phone's marker survives it. A fresh server "not registered" answer
        // wins over the marker and the run re-registers (wallet, foreground);
        // any other answer is reused by the activation check below, so this
        // adds no request. A cached or failed check changes nothing.
        known = await MobileStationStatusService(
          apiClient: repository.apiClient,
          db: db,
        ).fetch(owner);
        if (!known.cached && known.phase == MobileStationPhase.none) {
          await repository.registration.forget();
          locallyRegistered = false;
          known = null;
        }
      }
      if (proceed && pendingNow > 0 && !locallyRegistered) {
        // Unregistered (or registered only under M3's v1, without a collect
        // key, or forgotten by a reset): needs the wallet, so foreground only.
        proceed = await registerStation();
      }

      if (proceed && !checkWhenIdle) {
        proceed = await checkActivation(known: known);
      }

      while (proceed && failures < maxRetries) {
        // Registration and retries can consume the remaining upload window.
        droppedStale += await db.dropStaleReadingsWithNotice(
          _now().subtract(maxReadingAge),
        );
        notice = droppedStale > 0 ? staleReadingsNotice(droppedStale) : null;
        pendingNow = await db.getPendingSyncCount();
        if (pendingNow == 0) break;
        if (!await hasConnection()) {
          lastError = 'Connection lost during sync.';
          reason = SyncRunReason.connectionLost;
          break;
        }

        final readings = await db.getUnsyncedReadings(limit: maxBatchSize);
        if (readings.isEmpty) break;

        final result = await repository.submitBatch(
          readings,
          walletAddress: walletAddress,
          signer: collectKey!,
          includeIdempotencyKey: includeIdempotencyKey,
          isReadingFresh: (reading) =>
              !reading.timestamp.isBefore(_now().subtract(maxReadingAge)),
        );
        // A prepare/sign/submit delay can expire other rows in this batch.
        // Only unsynced rows are removed; admitted rows retain their history.
        droppedStale += await db.dropStaleReadingsWithNotice(
          _now().subtract(maxReadingAge),
        );
        notice = droppedStale > 0 ? staleReadingsNotice(droppedStale) : null;
        pendingNow = await db.getPendingSyncCount();
        acceptedCount += result.acceptedCount;
        failedCount += result.failedCount;
        lastSubmissionId = result.lastSubmissionId ?? lastSubmissionId;
        lastSubmissionStatus =
            result.lastSubmissionStatus ?? lastSubmissionStatus;
        rewardWrfTotal += result.rewardWrfTotal;
        rewardTotalsAvailable =
            rewardTotalsAvailable || result.rewardTotalsAvailable;

        if (result.refusal != null) {
          // The server's prepare disagreed with the phone's own computation:
          // nothing further is signed this run.
          reason = SyncRunReason.commitRefused;
          lastError = commitRefusedMessage;
          break;
        }

        final terminal = result.failure;
        if (terminal != null && terminal.stopsBatch) {
          if (terminal.isCollectKeyMismatch) {
            // The registered collect key is not ours (lost after a
            // reinstall/restore, or rotated out). A background run cannot
            // reach the wallet; a foreground run registers a NEW collect key,
            // once (design §11).
            if (openSession == null) {
              reason = SyncRunReason.awaitingReRegistration;
              lastError = reRegistrationNeededMessage(pendingNow);
              break;
            }
            if (!reRegistered) {
              reRegistered = true;
              await repository.registration.forget();
              if (await registerStation(freshKey: true, rotation: true)) {
                proceed = await checkActivation();
                continue;
              }
              break;
            }
          }
          if (terminal.isStationNotOwned &&
              openSession != null &&
              !reRegistered) {
            // One re-registration attempt per run, then stop (design §6.2).
            reRegistered = true;
            await repository.registration.forget();
            if (await registerStation()) {
              await applyStop(terminal);
              lastError = 'Station registration was renewed. This run stopped after an ownership rejection; readings are saved for the next sync.';
            }
            break;
          }
          // Never retry a terminal 4xx and never re-enter the loop after a
          // 429: keep the readings queued and end this run (mobile#334).
          await applyStop(terminal);
          break;
        }

        if (result.acceptedCount == 0 && result.failedCount > 0) {
          failures++;
          lastError = result.errorMessage ?? 'Failed to sync pending readings.';
          reason = SyncRunReason.failure;
          if (failures < maxRetries) {
            await _delay(backoffDelay(failures - 1));
          }
          continue;
        }

        failures = 0;
        if (result.failedCount > 0) {
          lastError =
              result.errorMessage ?? 'Some readings are still pending sync.';
          reason = SyncRunReason.partialFailure;
          break;
        }

        lastError = null;
        reason = SyncRunReason.success;
        if (readings.length < maxBatchSize) break;
      }

      final pendingAfter = await db.getPendingSyncCount();
      await _writeMetadata(
        db,
        pendingCount: pendingAfter,
        lastSyncAt: acceptedCount > 0 ? DateTime.now() : null,
        lastSyncAttemptAt: attemptedAt,
        lastSyncError:
            pendingAfter == 0 &&
                reason != SyncRunReason.awaitingActivation &&
                reason != SyncRunReason.activationUnknown
            ? null
            : lastError,
      );

      return await _buildResult(
        db,
        acceptedCount: acceptedCount,
        failedCount: failedCount,
        pendingCount: pendingAfter,
        message:
            pendingAfter == 0 &&
                reason != SyncRunReason.awaitingActivation &&
                reason != SyncRunReason.activationUnknown
            ? null
            : lastError,
        reason: pendingAfter == 0 && acceptedCount > 0
            ? SyncRunReason.success
            : reason,
        lastSubmissionId: lastSubmissionId,
        lastSubmissionStatus: lastSubmissionStatus,
        rewardWrfTotal: rewardWrfTotal,
        rewardTotalsAvailable: rewardTotalsAvailable,
        rejectedStatus: rejectedStatus,
        rejectedCode: rejectedCode,
        retryAfterUntil: retryAfterUntil,
        droppedStaleCount: droppedStale,
        notice: notice,
      );
    } finally {
      await db.close();
    }
  }

  static const String rateLimitedMessage =
      'Upload rate limit reached. Readings are saved and will upload later.';

  Future<DateTime?> _rateLimitedUntil() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // The foreground app and the Workmanager isolate share this value.
      await prefs.reload();
      final ms = prefs.getInt(nextAllowedAtKey);
      if (ms == null) return null;
      final until = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      final now = _now();
      if (until.isAfter(now.add(maxRateLimitBackoff))) {
        // Clock moved back or a stale/bad value: never lock beyond the cap.
        await prefs.remove(nextAllowedAtKey);
        return null;
      }
      return until.isAfter(now) ? until : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setNextAllowed(DateTime until) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        nextAllowedAtKey,
        until.toUtc().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Best effort: without persistence the next run just tries again.
    }
  }

  Duration backoffDelay(int attempt) {
    return Duration(seconds: 1 << attempt);
  }

  Future<void> _writeMetadata(
    AppDatabase db, {
    required int pendingCount,
    DateTime? lastSyncAt,
    DateTime? lastSyncAttemptAt,
    String? lastSyncError,
  }) {
    return db.upsertSyncMetadata(
      syncTableName: sensorReadingsSyncTableName,
      pendingCount: pendingCount,
      lastSyncAt: lastSyncAt,
      lastSyncAttemptAt: lastSyncAttemptAt,
      lastSyncError: lastSyncError,
    );
  }

  Future<SyncRunResult> _buildResult(
    AppDatabase db, {
    required int acceptedCount,
    required int failedCount,
    required int pendingCount,
    required String? message,
    required SyncRunReason reason,
    String? lastSubmissionId,
    String? lastSubmissionStatus,
    double rewardWrfTotal = 0,
    bool rewardTotalsAvailable = false,
    int? rejectedStatus,
    String? rejectedCode,
    DateTime? retryAfterUntil,
    int droppedStaleCount = 0,
    String? notice,
  }) async {
    final metadata = await db.getSyncMetadata(sensorReadingsSyncTableName);
    return SyncRunResult(
      acceptedCount: acceptedCount,
      failedCount: failedCount,
      pendingCount: pendingCount,
      lastSyncAt: metadata?.lastSyncAt,
      lastSyncAttemptAt: metadata?.lastSyncAttemptAt,
      message: message ?? metadata?.lastSyncError,
      reason: reason,
      lastSubmissionId: lastSubmissionId,
      lastSubmissionStatus: lastSubmissionStatus,
      rewardWrfTotal: rewardWrfTotal,
      rewardTotalsAvailable: rewardTotalsAvailable,
      rejectedStatus: rejectedStatus,
      rejectedCode: rejectedCode,
      retryAfterUntil: retryAfterUntil,
      droppedStaleCount: droppedStaleCount,
      notice: notice,
    );
  }
}

enum SyncRunReason {
  idle,
  offline,
  walletMissing,
  connectionLost,
  partialFailure,
  success,
  failure,
  stationNotRegistered,
  awaitingActivation,
  activationUnknown,
  rejected,
  rateLimited,

  /// A background run that needs the wallet (station not registered yet):
  /// readings wait for the app.
  awaitingForeground,

  /// A background run whose collect key was refused (`COLLECT_KEY_MISMATCH`):
  /// the app must re-register with a new one.
  awaitingReRegistration,

  /// The biometric prompt was refused; nothing was sent.
  signingRefused,

  /// The wallet cannot sign (legacy / inconsistent key).
  signingUnavailable,

  /// The server's registration answer did not match this wallet.
  registrationRefused,

  /// The server's prepare answer did not match the phone's own computation.
  commitRefused,
}

class SyncRunResult {
  final int acceptedCount;
  final int failedCount;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final DateTime? lastSyncAttemptAt;
  final String? message;
  final SyncRunReason reason;
  final String? lastSubmissionId;
  final String? lastSubmissionStatus;
  final double rewardWrfTotal;
  final bool rewardTotalsAvailable;

  /// HTTP status when [reason] is [SyncRunReason.rejected].
  final int? rejectedStatus;
  final String? rejectedCode;

  /// When sync may resume, for [SyncRunReason.rateLimited].
  final DateTime? retryAfterUntil;

  /// Queued readings removed this run for being past core4's acceptance
  /// window, and the one-time notice saying so.
  final int droppedStaleCount;
  final String? notice;

  const SyncRunResult({
    required this.acceptedCount,
    required this.failedCount,
    required this.pendingCount,
    required this.reason,
    this.lastSyncAt,
    this.lastSyncAttemptAt,
    this.message,
    this.lastSubmissionId,
    this.lastSubmissionStatus,
    this.rewardWrfTotal = 0,
    this.rewardTotalsAvailable = false,
    this.rejectedStatus,
    this.rejectedCode,
    this.retryAfterUntil,
    this.droppedStaleCount = 0,
    this.notice,
  });
}
