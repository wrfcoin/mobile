import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../services/offline/offline_data_buffer.dart';
import '../../data/models/current_conditions_model.dart';
import '../../data/models/forecast_model.dart';
import '../../data/models/alert_model.dart';
import '../../data/repositories/weather_repository_impl.dart';
import '../../data/weather_location_resolver.dart';
import '../../domain/models/coarse_location.dart';
import '../../../widgets/data/widget_snapshot_store.dart';

class WeatherState {
  final ForecastModel? forecast;
  final List<AlertModel> alerts;

  /// The latest observation (humidity, pressure). Null until loaded, and
  /// after a failed `/current` call: its failure never touches [error] or
  /// the forecast.
  final CurrentConditions? current;

  /// The forecast half of a load is in flight.
  final bool loading;

  /// The alerts half of a load is in flight, or will follow the forecast.
  final bool alertsLoading;

  /// The forecast's failure. An alerts result never touches it.
  final Failure? error;

  /// The alerts call's failure, kept apart from the forecast's. It stays
  /// until an alerts response succeeds.
  final Failure? alertsError;

  /// A successful alerts response has been received for the current
  /// location. Only then may an empty [alerts] list mean "all clear".
  final bool alertsLoaded;

  /// True when the currently displayed forecast was loaded from the local
  /// offline cache because the network was unavailable.
  final bool isFromCache;
  final DateTime? cachedAt;

  /// Why there is no usable location: permission is missing, location is
  /// off, or no fix arrived. Null when there is one. No weather request was
  /// made without one.
  final LocationUnavailableReason? locationUnavailable;

  /// There is no usable location; see [locationUnavailable].
  bool get locationNeeded => locationUnavailable != null;

  const WeatherState({
    this.forecast,
    this.alerts = const [],
    this.current,
    this.loading = false,
    this.alertsLoading = false,
    this.error,
    this.alertsError,
    this.alertsLoaded = false,
    this.isFromCache = false,
    this.cachedAt,
    this.locationUnavailable,
  });

  WeatherState copyWith({
    ForecastModel? forecast,
    List<AlertModel>? alerts,
    CurrentConditions? current,
    bool clearCurrent = false,
    bool? loading,
    bool? alertsLoading,
    Failure? error,
    Failure? alertsError,
    bool clearAlertsError = false,
    bool? alertsLoaded,
    bool? isFromCache,
    DateTime? cachedAt,
    LocationUnavailableReason? locationUnavailable,
    bool clearLocationUnavailable = false,
  }) {
    return WeatherState(
      forecast: forecast ?? this.forecast,
      alerts: alerts ?? this.alerts,
      current: clearCurrent ? null : current ?? this.current,
      loading: loading ?? this.loading,
      alertsLoading: alertsLoading ?? this.alertsLoading,
      error: error,
      alertsError: clearAlertsError ? null : alertsError ?? this.alertsError,
      alertsLoaded: alertsLoaded ?? this.alertsLoaded,
      isFromCache: isFromCache ?? this.isFromCache,
      cachedAt: cachedAt ?? this.cachedAt,
      // Only location resolution changes it; a load result never does.
      locationUnavailable: clearLocationUnavailable
          ? null
          : locationUnavailable ?? this.locationUnavailable,
    );
  }
}

class WeatherNotifier extends Notifier<WeatherState> {
  late WeatherRepository _repository;
  late WeatherLocationResolver _locationResolver;
  WeatherLocationRequest? _pendingLocation;
  OfflineDataBuffer? _offlineBuffer;

  /// Bumped by every [loadLocalWeather]. A result from an older load is
  /// dropped, so a late answer cannot overwrite a newer state, e.g. the
  /// no-location state after permission is revoked.
  int _generation = 0;

  /// The location key [WeatherState.current] was loaded for. A load for a
  /// different key clears it, so one place's humidity and pressure never
  /// sit beside another place's forecast.
  String? _currentFor;

  @override
  WeatherState build() {
    _repository = ref.watch(weatherRepositoryProvider);
    _locationResolver = ref.watch(weatherLocationResolverProvider);
    // OfflineDataBuffer requires AppDatabase; it is only available on native.
    // On web, pass null — the notifier falls back to direct repository calls.
    try {
      _offlineBuffer = ref.watch(offlineDataBufferProvider);
    } catch (_) {
      _offlineBuffer = null;
    }
    // Register sync-on-reconnect callback so the weather refreshes
    // automatically when the device regains connectivity. It goes through
    // loadLocalWeather, which re-checks permission: a revoked permission
    // means no request, and never a reuse of an earlier location.
    _offlineBuffer?.registerSyncCallback('weather:forecast', loadLocalWeather);
    ref.onDispose(() {
      _offlineBuffer?.unregisterSyncCallback('weather:forecast');
      _pendingLocation?.cancel();
    });
    return const WeatherState();
  }

  /// Resolves the device's rounded location and loads the forecast and
  /// alerts for it. Without a location, makes no request and sets
  /// [WeatherState.locationUnavailable].
  Future<void> loadLocalWeather() async {
    final generation = ++_generation;
    state = state.copyWith(loading: true, alertsLoading: true, error: null);
    _pendingLocation?.cancel();
    final request = _pendingLocation = _locationResolver.request();
    final result = await request.result;
    if (!_isCurrent(generation)) return;
    _pendingLocation = null;
    final location = result.location;
    if (location == null) {
      _currentFor = null;
      state = WeatherState(locationUnavailable: result.reason);
      return;
    }
    state = state.copyWith(
      error: state.error,
      clearLocationUnavailable: true,
      clearCurrent: location.pathSegment != _currentFor,
    );
    await loadForecast(location);
    if (!_isCurrent(generation)) return;
    // /current runs beside alerts, so a slow one does not delay them. Each
    // is generation-guarded on its own.
    await Future.wait([loadCurrent(location), loadAlerts(location)]);
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  Future<void> loadForecast(CoarseLocation location) async {
    final generation = _generation;
    state = state.copyWith(loading: true, error: null);

    final buffer = _offlineBuffer;
    if (buffer != null) {
      final result = await buffer.fetchWithCache<ForecastModel>(
        cacheKey: 'weather:forecast:${location.pathSegment}',
        fetch: () => _repository.getForecast(location),
        fromJson: ForecastModel.fromJson,
        toJson: (f) => f.toJson(),
      );
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        loading: false,
        forecast: result.valueOrNull,
        error: result.failure,
        isFromCache: result.isFromCache,
        cachedAt: result.cachedAt,
      );
      await _persistWidgetForecast();
    } else {
      // Fallback path (e.g. web, or when DB provider is not overridden).
      final result = await _repository.getForecast(location);
      if (!_isCurrent(generation)) return;
      result.fold(
        (failure) => state = state.copyWith(loading: false, error: failure),
        (forecast) => state = state.copyWith(
          loading: false,
          forecast: forecast,
          isFromCache: false,
        ),
      );
      await _persistWidgetForecast();
    }
  }

  /// Loads humidity and pressure. A failure leaves them null ("Not
  /// available") and touches nothing else, so the forecast still shows.
  Future<void> loadCurrent(CoarseLocation location) async {
    final generation = _generation;
    final result = await _repository.getCurrentConditions(location);
    if (!_isCurrent(generation)) return;
    result.fold(
      (_) {
        _currentFor = null;
        state = state.copyWith(error: state.error, clearCurrent: true);
      },
      (current) {
        _currentFor = location.pathSegment;
        state = state.copyWith(error: state.error, current: current);
      },
    );
  }

  Future<void> _persistWidgetForecast() async {
    await WidgetSnapshotStore().writeWeatherSlice(state.forecast);
  }

  Future<void> loadAlerts(CoarseLocation location) async {
    final generation = _generation;
    state = state.copyWith(error: state.error, alertsLoading: true);
    final result = await _repository.getActiveAlerts(location);
    if (!_isCurrent(generation)) return;
    // Carry the forecast's error through: copyWith clears what it is not
    // given, and an alerts result must not erase a forecast failure.
    result.fold(
      // A failed refresh drops the old list: stale alerts are not current.
      (failure) => state = state.copyWith(
        error: state.error,
        alerts: const [],
        alertsError: failure,
        alertsLoaded: false,
        alertsLoading: false,
      ),
      (alerts) => state = state.copyWith(
        error: state.error,
        alerts: alerts,
        clearAlertsError: true,
        alertsLoaded: true,
        alertsLoading: false,
      ),
    );
  }
}

final weatherProvider = NotifierProvider<WeatherNotifier, WeatherState>(
  WeatherNotifier.new,
);
