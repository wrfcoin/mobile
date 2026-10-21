import '../../../weather/domain/models/coarse_location.dart';

import 'dart:async';

// Lane 1 (earn-loop-live): connectivity watch for auto-sync on reconnect
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;

import '../../../../core/feature_flags/feature_flags.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../data/models/sensor_reading_model.dart';
import '../../data/repositories/collector_repository_impl.dart';
import '../../data/services/collector_preferences.dart';
import '../../data/services/sampling_policy.dart';
import '../../../../services/background/sensor_worker.dart';
import '../../../../services/background/sync_worker.dart';
import '../../../../services/storage/local_db.dart';
import 'mobile_station_status_provider.dart';
import '../../../widgets/data/widget_snapshot_store.dart';
import '../../../../services/observability/app_logger.dart';
import '../../../wear/services/wear_companion_bridge.dart';

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  return SyncWorker();
});

class CollectorState {
  static const _noChange = Object();

  final bool isCollecting;
  final bool isCollectingNow;
  // Lane 1: tracks an in-progress background sync so the UI can block redundant
  // manual collects and show a progress indicator.
  final bool isSyncing;
  // Lane 2: set to true once persisted settings have been loaded from
  // SharedPreferences so settings-gated UI can wait before rendering.
  final bool settingsLoaded;
  final SensorReadingModel? currentReading;
  final int pendingSyncCount;
  final int staleReadingsCount;
  final int syncedSubmissionCount;
  final bool rewardTotalsAvailable;
  final double earnedRewardWrf;
  final int intervalMinutes;
  final int batteryThreshold;
  final DateTime? lastSyncAt;
  final DateTime? lastSyncAttemptAt;
  final String? syncMessage;
  final String? lastSubmissionId;
  final String? lastSubmissionStatus;

  const CollectorState({
    this.isCollecting = false,
    this.isCollectingNow = false,
    this.isSyncing = false,
    this.settingsLoaded = false,
    this.currentReading,
    this.pendingSyncCount = 0,
    this.staleReadingsCount = 0,
    this.syncedSubmissionCount = 0,
    this.rewardTotalsAvailable = false,
    this.earnedRewardWrf = 0,
    this.intervalMinutes = 15,
    this.batteryThreshold = 15,
    this.lastSyncAt,
    this.lastSyncAttemptAt,
    this.syncMessage,
    this.lastSubmissionId,
    this.lastSubmissionStatus,
  });

  CollectorState copyWith({
    bool? isCollecting,
    bool? isCollectingNow,
    bool? isSyncing,
    bool? settingsLoaded,
    SensorReadingModel? currentReading,
    int? pendingSyncCount,
    int? staleReadingsCount,
    int? syncedSubmissionCount,
    bool? rewardTotalsAvailable,
    double? earnedRewardWrf,
    int? intervalMinutes,
    int? batteryThreshold,
    Object? lastSyncAt = _noChange,
    Object? lastSyncAttemptAt = _noChange,
    Object? syncMessage = _noChange,
    Object? lastSubmissionId = _noChange,
    Object? lastSubmissionStatus = _noChange,
  }) {
    return CollectorState(
      isCollecting: isCollecting ?? this.isCollecting,
      isCollectingNow: isCollectingNow ?? this.isCollectingNow,
      isSyncing: isSyncing ?? this.isSyncing,
      settingsLoaded: settingsLoaded ?? this.settingsLoaded,
      currentReading: currentReading ?? this.currentReading,
      pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
      staleReadingsCount: staleReadingsCount ?? this.staleReadingsCount,
      syncedSubmissionCount:
          syncedSubmissionCount ?? this.syncedSubmissionCount,
      rewardTotalsAvailable:
          rewardTotalsAvailable ?? this.rewardTotalsAvailable,
      earnedRewardWrf: earnedRewardWrf ?? this.earnedRewardWrf,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      batteryThreshold: batteryThreshold ?? this.batteryThreshold,
      lastSyncAt: identical(lastSyncAt, _noChange)
          ? this.lastSyncAt
          : lastSyncAt as DateTime?,
      lastSyncAttemptAt: identical(lastSyncAttemptAt, _noChange)
          ? this.lastSyncAttemptAt
          : lastSyncAttemptAt as DateTime?,
      syncMessage: identical(syncMessage, _noChange)
          ? this.syncMessage
          : syncMessage as String?,
      lastSubmissionId: identical(lastSubmissionId, _noChange)
          ? this.lastSubmissionId
          : lastSubmissionId as String?,
      lastSubmissionStatus: identical(lastSubmissionStatus, _noChange)
          ? this.lastSubmissionStatus
          : lastSubmissionStatus as String?,
    );
  }
}

class CollectorNotifier extends Notifier<CollectorState> {
  late CollectorRepository _repository;
  late SyncWorker _syncWorker;
  late CollectorPreferences _preferences;
  late AppPreferencesStore _appPreferencesStore;
  late AppLogger _logger;
  late bool _enableConnectivityHardening;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  CollectorState build() {
    _repository = ref.watch(collectorRepositoryProvider);
    _syncWorker = ref.watch(syncWorkerProvider);
    _preferences = ref.watch(collectorPreferencesProvider);
    _appPreferencesStore = ref.watch(appPreferencesStoreProvider);
    _logger = ref.watch(appLoggerProvider);
    _enableConnectivityHardening = ref
        .watch(featureFlagsProvider)
        .enableConnectivityHardening;

    unawaited(_restoreState());
    if (!kIsWeb) {
      _connectivitySubscription = _syncWorker.onConnectivityChanged.listen((
        results,
      ) {
        if (!results.contains(ConnectivityResult.none)) {
          unawaited(autoSyncPendingData());
        }
      });
    }
    ref.onDispose(() {
      _connectivitySubscription?.cancel();
    });
    return const CollectorState();
  }

  Future<void> startCollecting() async {
    if (!await _hasCollectionConsent()) {
      state = state.copyWith(
        syncMessage: 'Grant sensor and location consent in Privacy Center to enable collection.',
      );
      return;
    }
    await _scheduleWorkers();
    state = state.copyWith(isCollecting: true, syncMessage: null);
    await _persistPreferences();
  }

  Future<void> stopCollecting() async {
    await cancelCollectionWorkers();
    state = state.copyWith(isCollecting: false, isSyncing: false);
    await _persistPreferences();
  }

  Future<void> collectNow() async {
    if (state.isCollectingNow) return;
    ref.invalidate(mobileStationStatusProvider);
    if (!await _hasCollectionConsent()) {
      state = state.copyWith(
        syncMessage: 'Grant sensor and location consent in Privacy Center to enable collection.',
      );
      return;
    }

    state = state.copyWith(isCollectingNow: true, syncMessage: null);
    try {
      final result = await _repository.collectReading(
        batteryThreshold: state.batteryThreshold,
        baseIntervalMinutes: state.intervalMinutes,
        force: true,
      );
      await _refreshSyncMetadata(currentReading: result.reading);
      await _publishHomeWidgetCollectionSlice(reading: result.reading);

      if (!result.isSuccess) {
        final message = _collectionFailureMessage(result.failureReason);
        state = state.copyWith(syncMessage: message);
        _logger.warning(
          'collector_collect_failed',
          fields: <String, dynamic>{
            'reason': _collectionFailureCode(result.failureReason),
            'batteryThreshold': state.batteryThreshold,
            'intervalMinutes': state.intervalMinutes,
            'pendingCount': state.pendingSyncCount,
          },
        );
        await _logValidationEvent(
          code: _collectionFailureCode(result.failureReason),
          message: message,
        );
        return;
      }

      final reading = result.reading!;
      unawaited(_publishReadingToCompanion(reading));
      _logger.info(
        'collector_collect_success',
        fields: <String, dynamic>{
          'pressureHpa': reading.pressureHpa,
          'latitude': CoarseLocation.coarsen(reading.latitude),
          'longitude': CoarseLocation.coarsen(reading.longitude),
          'pendingCount': state.pendingSyncCount,
        },
      );
      await _logValidationEvent(
        code: 'collect_success',
        message:
            'Captured ${reading.pressureHpa.toStringAsFixed(1)} hPa at '
            '${CoarseLocation.coarsen(reading.latitude).toStringAsFixed(1)}, '
            '${CoarseLocation.coarsen(reading.longitude).toStringAsFixed(1)}.',
      );

      if (!kIsWeb) {
        await syncPendingData();
      }
    } finally {
      state = state.copyWith(isCollectingNow: false);
    }
  }

  Future<void> _publishReadingToCompanion(SensorReadingModel reading) async {
    try {
      final deliveredNodes = await WearCompanionBridge()
          .publishReading(reading)
          .timeout(const Duration(milliseconds: 2500));
      _logger.info(
        'collector_wear_publish_complete',
        fields: <String, dynamic>{
          'pressureHpa': reading.pressureHpa,
          'deliveredNodes': deliveredNodes,
        },
      );
    } on TimeoutException {
      _logger.warning(
        'collector_wear_publish_timeout',
        fields: <String, dynamic>{
          'pressureHpa': reading.pressureHpa,
          'capturedAt': reading.timestamp.toIso8601String(),
        },
      );
    } on MissingPluginException {
      _logger.info('collector_wear_publish_skipped_no_plugin');
    } on PlatformException {
      _logger.warning(
        'collector_wear_publish_platform_error',
        fields: <String, dynamic>{'pressureHpa': reading.pressureHpa},
      );
    } catch (error) {
      _logger.warning(
        'collector_wear_publish_failed',
        fields: <String, dynamic>{
          'pressureHpa': reading.pressureHpa,
          'error': error.toString(),
        },
      );
    }
  }

  /// Set when the biometric prompt was cancelled; the automatic triggers then
  /// stand down (no prompt loop, design §200) until [syncPendingData] runs.
  bool _signingRefused = false;

  /// Sync triggered by the app itself on reconnect. Collect Now is explicit.
  @visibleForTesting
  Future<void> autoSyncPendingData() async {
    if (_signingRefused) return;
    await syncPendingData();
  }

  /// One lifecycle check; a cancelled signing prompt stays user-rearmed.
  Future<void> handleAppResume() async {
    ref.invalidate(mobileStationStatusProvider);
    if (_signingRefused) return;
    await syncPendingData(fromResume: true);
  }

  /// Explicit sync re-arms automatic triggers unless signing is refused.
  Future<void> syncPendingData({bool fromResume = false}) async {
    if (kIsWeb) return;
    if (state.isSyncing) return;

    state = state.copyWith(isSyncing: true, syncMessage: null);
    try {
      final result = fromResume
          ? await _syncWorker.syncOnResume(
              includeIdempotencyKey: _enableConnectivityHardening,
            )
          : await _syncWorker.syncPendingReadings(
              includeIdempotencyKey: _enableConnectivityHardening,
            );
      await _refreshStaleReadingsCount();
      ref.invalidate(mobileStationStatusProvider);
      _signingRefused = result.reason == SyncRunReason.signingRefused;
      final syncedSubmissionCount =
          state.syncedSubmissionCount + result.acceptedCount;
      final rewardTotalsAvailable =
          state.rewardTotalsAvailable || result.rewardTotalsAvailable;
      final earnedRewardWrf = state.earnedRewardWrf + result.rewardWrfTotal;

      state = state.copyWith(
        isSyncing: false,
        pendingSyncCount: result.pendingCount,
        syncedSubmissionCount: syncedSubmissionCount,
        rewardTotalsAvailable: rewardTotalsAvailable,
        earnedRewardWrf: earnedRewardWrf,
        lastSyncAt: result.lastSyncAt,
        lastSyncAttemptAt: result.lastSyncAttemptAt,
        syncMessage: result.message,
        lastSubmissionId: result.lastSubmissionId,
        lastSubmissionStatus: result.lastSubmissionStatus,
      );
      _logger.info(
        'collector_sync_result',
        fields: <String, dynamic>{
          'reason': result.reason.name,
          'acceptedCount': result.acceptedCount,
          'failedCount': result.failedCount,
          'pendingCount': result.pendingCount,
          'rewardTotalsAvailable': result.rewardTotalsAvailable,
          'rewardWrfTotal': result.rewardWrfTotal,
          'lastSubmissionId': result.lastSubmissionId,
          'lastSubmissionStatus': result.lastSubmissionStatus,
          'message': result.message,
        },
      );
      await _persistPreferences();
      await _logValidationEvent(
        code: _syncEventCode(
          result.reason,
          status: result.rejectedStatus,
          code: result.rejectedCode,
        ),
        message: _syncEventMessage(result),
      );
      await _publishHomeWidgetCollectionSlice();
    } catch (error) {
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Sync failed: $error',
      );
      _logger.error(
        'collector_sync_failed',
        fields: <String, dynamic>{
          'error': error.toString(),
          'pendingCount': state.pendingSyncCount,
        },
      );
      await _refreshSyncMetadata();
      await _logValidationEvent(
        code: 'sync_failed',
        message: 'Sync failed before completion: $error',
      );
      await _publishHomeWidgetCollectionSlice();
    }
  }

  Future<void> _publishHomeWidgetCollectionSlice({
    SensorReadingModel? reading,
  }) async {
    await WidgetSnapshotStore().writeCollectionSlice(
      reading: reading,
      pendingSyncCount: state.pendingSyncCount,
      lastSubmissionStatus: state.lastSubmissionStatus,
      rewardTotalsAvailable: state.rewardTotalsAvailable,
      earnedRewardWrf: state.earnedRewardWrf,
    );
  }

  Future<void> refreshSyncCount() async {
    await _refreshSyncMetadata();
    ref.invalidate(mobileStationStatusProvider);
  }

  Future<void> acknowledgeStaleReadings() async {
    final store = _repository.db;
    if (store is AppDatabase) {
      await store.acknowledgeStaleReadings(state.staleReadingsCount);
    }
    await _refreshStaleReadingsCount();
  }

  Future<void> _refreshStaleReadingsCount() async {
    final notice = await _repository.db.getSyncMetadata(
      staleReadingsNoticeTableName,
    );
    state = state.copyWith(
      staleReadingsCount: notice?.syncTableName == staleReadingsNoticeTableName
          ? notice!.pendingCount
          : 0,
    );
  }

  Future<void> setInterval(int minutes) async {
    state = state.copyWith(intervalMinutes: minutes);
    await _persistPreferences();
    if (state.isCollecting) {
      await _scheduleWorkers();
    }
  }

  Future<void> setBatteryThreshold(int threshold) async {
    state = state.copyWith(batteryThreshold: threshold);
    await _persistPreferences();
    if (state.isCollecting) {
      await _scheduleWorkers();
    }
  }

  Future<void> _restoreState() async {
    final preferences = await _preferences.load();
    final appPreferences = await _appPreferencesStore.load();
    final canCollect = appPreferences.consent.canCollect;
    state = state.copyWith(
      isCollecting: kIsWeb ? false : preferences.isCollecting && canCollect,
      intervalMinutes: preferences.intervalMinutes,
      batteryThreshold: preferences.batteryThreshold,
      syncedSubmissionCount: preferences.syncedSubmissionCount,
      rewardTotalsAvailable: preferences.rewardTotalsAvailable,
      earnedRewardWrf: preferences.earnedRewardWrf,
      lastSubmissionId: preferences.lastSubmissionId,
      lastSubmissionStatus: preferences.lastSubmissionStatus,
      // Lane 2: mark settings as loaded so settings-gated UI can render
      settingsLoaded: true,
    );
    if (kIsWeb) return;
    await _refreshSyncMetadata();

    if (preferences.isCollecting && canCollect && !kIsWeb) {
      await _scheduleWorkers();
    }
  }

  Future<void> _scheduleWorkers() async {
    final intervalMinutes = await _repository.recommendedIntervalMinutes(
      state.intervalMinutes,
    );
    await registerSensorWorker(interval: Duration(minutes: intervalMinutes));
    await registerSyncWorker();
  }

  Future<void> _persistPreferences() {
    return _preferences.save(
      CollectorPreferencesState(
        isCollecting: state.isCollecting,
        intervalMinutes: state.intervalMinutes,
        batteryThreshold: state.batteryThreshold,
        syncedSubmissionCount: state.syncedSubmissionCount,
        rewardTotalsAvailable: state.rewardTotalsAvailable,
        earnedRewardWrf: state.earnedRewardWrf,
        lastSubmissionId: state.lastSubmissionId,
        lastSubmissionStatus: state.lastSubmissionStatus,
      ),
    );
  }

  Future<void> _refreshSyncMetadata({
    SensorReadingModel? currentReading,
  }) async {
    await _refreshStaleReadingsCount();
    final metadata = await _repository.getSyncMetadata();
    final count = await _repository.getUnsyncedCount();
    state = state.copyWith(
      currentReading: currentReading ?? state.currentReading,
      pendingSyncCount: count,
      lastSyncAt: metadata?.lastSyncAt,
      lastSyncAttemptAt: metadata?.lastSyncAttemptAt,
      syncMessage: metadata?.lastSyncError,
    );
  }

  Future<void> saveSettings({
    required int intervalMinutes,
    required int batteryThreshold,
  }) async {
    state = state.copyWith(
      intervalMinutes: intervalMinutes,
      batteryThreshold: batteryThreshold,
    );
    await _persistPreferences();

    if (state.isCollecting) {
      await registerSensorWorker(interval: Duration(minutes: intervalMinutes));
    }
  }

  Future<void> handleConsentRevoked() async {
    await cancelCollectionWorkers();
    await Future.wait([
      _repository.db.clearUnsyncedReadings(),
      _repository.db.clearPendingImages(),
      _repository.db.clearSyncMetadata(sensorReadingsSyncTableName),
      _repository.db.clearSyncMetadata(staleReadingsNoticeTableName),
    ]);
    state = state.copyWith(
      isCollecting: false,
      isCollectingNow: false,
      isSyncing: false,
      currentReading: null,
      pendingSyncCount: 0,
      staleReadingsCount: 0,
      lastSyncAt: null,
      lastSyncAttemptAt: null,
      syncMessage:
          'Collection consent revoked. Pending local data was cleared.',
    );
    await _persistPreferences();
  }

  Future<bool> _hasCollectionConsent() async {
    final preferences = await _appPreferencesStore.load();
    return preferences.consent.canCollect;
  }

  Future<void> clearValidationEvents() {
    return _preferences.clearValidationEvents();
  }

  Future<void> _logValidationEvent({
    required String code,
    required String message,
  }) {
    return _preferences.appendValidationEvent(
      CollectorValidationEvent(
        timestamp: DateTime.now(),
        code: code,
        message: message,
      ),
    );
  }

  String _collectionFailureCode(CollectReadingFailureReason? reason) {
    switch (reason) {
      case CollectReadingFailureReason.batteryLow:
        return 'battery_low';
      case CollectReadingFailureReason.barometerUnavailable:
        return 'barometer_unavailable';
      case CollectReadingFailureReason.locationUnavailable:
        return 'location_unavailable';
      case CollectReadingFailureReason.stationaryBackoff:
        return 'stationary_backoff';
      case null:
        return 'collect_failed';
    }
  }

  String _collectionFailureMessage(CollectReadingFailureReason? reason) {
    switch (reason) {
      case CollectReadingFailureReason.batteryLow:
        return 'Collection paused because battery is below the configured threshold.';
      case CollectReadingFailureReason.barometerUnavailable:
        return 'No barometer reading was available on this device.';
      case CollectReadingFailureReason.locationUnavailable:
        return 'Allow location to register your weather station, then try Collect Now again.';
      case CollectReadingFailureReason.stationaryBackoff:
        return 'Collection backed off because the device has not moved enough yet.';
      case null:
        return 'No sensor reading captured. Check permissions, device sensors, or battery settings.';
    }
  }

  String _syncEventCode(SyncRunReason reason, {int? status, String? code}) {
    switch (reason) {
      case SyncRunReason.idle:
        return 'sync_idle';
      case SyncRunReason.offline:
        return 'offline';
      case SyncRunReason.walletMissing:
        return 'wallet_missing';
      case SyncRunReason.connectionLost:
        return 'connection_lost';
      case SyncRunReason.partialFailure:
        return 'sync_partial';
      case SyncRunReason.success:
        return 'sync_success';
      case SyncRunReason.failure:
        return 'sync_failed';
      case SyncRunReason.stationNotRegistered:
        return 'station_not_registered';
      case SyncRunReason.awaitingActivation:
        return 'station_awaiting_activation';
      case SyncRunReason.activationUnknown:
        return 'station_activation_unknown';
      case SyncRunReason.rejected:
        if (status == 401) return 'session_expired';
        if (status == 409 && code == 'STATION_ID_TAKEN') {
          return 'station_id_taken';
        }
        if (status == 400 || status == 422) return 'validation_rejected';
        return 'sync_rejected';
      case SyncRunReason.rateLimited:
        return 'sync_rate_limited';
      case SyncRunReason.awaitingForeground:
        return 'sync_awaiting_foreground';
      case SyncRunReason.awaitingReRegistration:
        return 'sync_awaiting_reregistration';
      case SyncRunReason.signingRefused:
        return 'sync_signing_refused';
      case SyncRunReason.signingUnavailable:
        return 'sync_signing_unavailable';
      case SyncRunReason.registrationRefused:
        return 'station_registration_refused';
      case SyncRunReason.commitRefused:
        return 'sync_commit_refused';
    }
  }

  String _syncEventMessage(SyncRunResult result) {
    final buffer = StringBuffer();
    buffer.write(
      'accepted=${result.acceptedCount}, failed=${result.failedCount}, pending=${result.pendingCount}',
    );
    if (result.rejectedStatus != null) {
      buffer.write(', status=${result.rejectedStatus}');
    }
    if (result.lastSubmissionId != null) {
      buffer.write(', submission=${result.lastSubmissionId}');
    }
    if (result.lastSubmissionStatus != null) {
      buffer.write(', status=${result.lastSubmissionStatus}');
    }
    if (result.message != null && result.message!.isNotEmpty) {
      buffer.write(', message=${result.message}');
    }
    return buffer.toString();
  }
}

final collectorProvider = NotifierProvider<CollectorNotifier, CollectorState>(
  CollectorNotifier.new,
);

final batteryImpactEstimateProvider = Provider<BatteryImpactEstimate>((ref) {
  final state = ref.watch(collectorProvider);
  return SamplingPolicy.estimateImpact(
    intervalMinutes: state.intervalMinutes,
    batteryThreshold: state.batteryThreshold,
  );
});
