import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/time/app_clock.dart';
import '../../../../services/offline/offline_data_buffer.dart';
import '../../data/models/current_conditions_model.dart';
import '../../data/models/forecast_detail_model.dart';
import '../../data/models/forecast_model.dart';
import '../../data/models/alert_model.dart';
import '../../data/repositories/weather_repository_impl.dart';
import '../../data/weather_location_resolver.dart';
import '../../domain/models/coarse_location.dart';
import '../../../widgets/data/widget_snapshot_store.dart';

/// Weather older than this is fetched again the next time the tab is on
/// screen. Every load is three calls in the rate-limited NOAA zone, so a tab
/// switch alone never makes one.
const weatherStaleAfter = Duration(minutes: 10);

/// How long after a load, successful or not, an automatic one may start.
/// Pull to refresh and Retry do not wait.
const weatherRetryAfter = Duration(minutes: 5);

class WeatherState {
  final ForecastModel? forecast;
  final List<AlertModel> alerts;

  /// The days from the response that gave [forecast]. Null when it had none.
  final List<DailyForecast>? daily;

  /// The hourly periods for [forecast]'s location. Null until loaded and after
  /// a failed call on an otherwise good refresh.
  final List<HourlyForecast>? hourly;
  final bool hourlyLoading;
  final Failure? hourlyError;

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

  /// When [forecast] was fetched: the cache time if it came from the cache.
  /// A failed refresh leaves it alone, so it always says how old [forecast]
  /// really is.
  final DateTime? lastUpdated;

  /// Why there is no usable location: permission is missing, location is
  /// off, or no fix arrived. Null when there is one. No weather request was
  /// made without one.
  final LocationUnavailableReason? locationUnavailable;

  /// There is no usable location; see [locationUnavailable].
  bool get locationNeeded => locationUnavailable != null;

  const WeatherState({
    this.forecast,
    this.alerts = const [],
    this.daily,
    this.hourly,
    this.hourlyLoading = false,
    this.hourlyError,
    this.current,
    this.loading = false,
    this.alertsLoading = false,
    this.error,
    this.alertsError,
    this.alertsLoaded = false,
    this.isFromCache = false,
    this.cachedAt,
    this.lastUpdated,
    this.locationUnavailable,
  });

  WeatherState copyWith({
    ForecastModel? forecast,
    bool clearForecast = false,
    List<DailyForecast>? daily,
    List<HourlyForecast>? hourly,
    bool clearHourly = false,
    bool? hourlyLoading,
    Failure? hourlyError,
    bool clearHourlyError = false,
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
    DateTime? lastUpdated,
    LocationUnavailableReason? locationUnavailable,
    bool clearLocationUnavailable = false,
  }) {
    return WeatherState(
      forecast: clearForecast ? null : forecast ?? this.forecast,
      daily: clearForecast ? daily : daily ?? this.daily,
      hourly: clearForecast || clearHourly ? hourly : hourly ?? this.hourly,
      hourlyLoading: hourlyLoading ?? this.hourlyLoading,
      hourlyError: clearHourlyError ? null : hourlyError ?? this.hourlyError,
      alerts: alerts ?? this.alerts,
      current: clearCurrent ? null : current ?? this.current,
      loading: loading ?? this.loading,
      alertsLoading: alertsLoading ?? this.alertsLoading,
      error: error,
      alertsError: clearAlertsError ? null : alertsError ?? this.alertsError,
      alertsLoaded: alertsLoaded ?? this.alertsLoaded,
      isFromCache: isFromCache ?? this.isFromCache,
      cachedAt: cachedAt ?? this.cachedAt,
      lastUpdated: clearForecast
          ? lastUpdated
          : lastUpdated ?? this.lastUpdated,
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

  /// The location key [WeatherState.forecast] and its alerts were loaded for.
  /// As with [_currentFor], another place's weather is never kept on screen.
  String? _forecastFor;

  /// The location of the latest load, for [retryHourly].
  CoarseLocation? _hourlyLocation;

  /// When the latest load started; see [weatherRetryAfter].
  DateTime? _lastAttempt;

  DateTime _now() => ref.read(appClockProvider)();

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
    _lastAttempt = _now();
    state = state.copyWith(loading: true, alertsLoading: true, error: null);
    _pendingLocation?.cancel();
    final request = _pendingLocation = _locationResolver.request();
    final result = await request.result;
    if (!_isCurrent(generation)) return;
    _pendingLocation = null;
    final location = result.location;
    if (location == null) {
      _currentFor = null;
      _forecastFor = null;
      state = WeatherState(locationUnavailable: result.reason);
      return;
    }
    final moved = _forecastFor != null && location.pathSegment != _forecastFor;
    if (moved) {
      _forecastFor = null;
      state = state.copyWith(
        clearForecast: true,
        hourlyLoading: false,
        clearHourlyError: true,
        alerts: const [],
        alertsLoaded: false,
        clearAlertsError: true,
        isFromCache: false,
      );
    }
    state = state.copyWith(
      error: state.error,
      clearLocationUnavailable: true,
      clearCurrent: location.pathSegment != _currentFor,
    );
    await loadForecast(location);
    if (!_isCurrent(generation)) return;
    _hourlyLocation = location;
    // These run beside each other, so a slow one does not delay the others.
    // Each is generation-guarded on its own. A round that got no new forecast
    // spends no further call on hourly: the old hours stay with the old
    // forecast, under its note.
    await Future.wait([
      loadCurrent(location),
      loadAlerts(location),
      if (state.error == null && !state.isFromCache) loadHourly(location),
    ]);
  }

  /// Loads if the weather on screen is old enough. Keeps it on screen while
  /// loading, and does nothing while a load is running.
  Future<void> refreshIfStale() async {
    if (!_mayLoadNow) return;
    final updated = state.lastUpdated;
    if (updated != null && _now().difference(updated) < weatherStaleAfter) {
      return;
    }
    await loadLocalWeather();
  }

  /// The Weather tab came back on screen, or the app came back to the front.
  /// Fresh weather stays as it is unless the permission or the place changed,
  /// which a cheap look at the platform can tell without a fresh fix.
  Future<void> onVisible() async {
    final generation = _generation;
    final seen = await _locationResolver.peek();
    if (!_isCurrent(generation) || _isLoading) return;
    final reason = seen?.reason;
    final location = seen?.location;
    final changed =
        (seen == null && state.locationNeeded) ||
        (reason != null && reason != state.locationUnavailable) ||
        (location != null &&
            (state.locationNeeded ||
                (_forecastFor != null &&
                    location.pathSegment != _forecastFor)));
    if (changed) {
      await loadLocalWeather();
    } else {
      await refreshIfStale();
    }
  }

  bool get _isLoading => state.loading || state.alertsLoading;

  bool get _mayLoadNow {
    if (_isLoading) return false;
    final attempt = _lastAttempt;
    return attempt == null || _now().difference(attempt) >= weatherRetryAfter;
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  Future<void> loadForecast(CoarseLocation location) async {
    final generation = _generation;
    state = state.copyWith(loading: true, error: null);

    final buffer = _offlineBuffer;
    if (buffer != null) {
      List<DailyForecast>? daily;
      final result = await buffer.fetchWithCache<ForecastModel>(
        cacheKey: 'weather:forecast:${location.pathSegment}',
        fetch: () async {
          final fetched = await _repository.getForecastWithDaily(location);
          return fetched.map((both) {
            daily = both.daily;
            return both.forecast;
          });
        },
        fromJson: ForecastModel.fromJson,
        toJson: (f) => f.toJson(),
      );
      if (!_isCurrent(generation)) return;
      final fetched = result.valueOrNull;
      if (fetched != null) _forecastFor = location.pathSegment;
      state = state.copyWith(
        loading: false,
        forecast: fetched,
        daily: daily,
        error: result.failure,
        isFromCache: result.isFromCache,
        cachedAt: result.cachedAt,
        lastUpdated: fetched == null
            ? null
            : result.isFromCache
            ? result.cachedAt
            : _now(),
      );
      await _persistWidgetForecast();
    } else {
      // Fallback path (e.g. web, or when DB provider is not overridden).
      final result = await _repository.getForecastWithDaily(location);
      if (!_isCurrent(generation)) return;
      result.fold(
        (failure) => state = state.copyWith(loading: false, error: failure),
        (both) {
          _forecastFor = location.pathSegment;
          state = state.copyWith(
            loading: false,
            forecast: both.forecast,
            daily: both.daily,
            isFromCache: false,
            lastUpdated: _now(),
          );
        },
      );
      await _persistWidgetForecast();
    }
  }

  /// Loads humidity and pressure. A failure leaves them null ("Not
  /// available") and touches nothing else, so the forecast still shows. The
  /// exception is a refresh that failed altogether: the old reading then stays
  /// with the old forecast, under its "last updated" note.
  Future<void> loadCurrent(CoarseLocation location) async {
    final generation = _generation;
    final result = await _repository.getCurrentConditions(location);
    if (!_isCurrent(generation)) return;
    result.fold(
      (_) {
        if (state.error != null && _currentFor == location.pathSegment) return;
        _currentFor = null;
        state = state.copyWith(error: state.error, clearCurrent: true);
      },
      (current) {
        _currentFor = location.pathSegment;
        state = state.copyWith(error: state.error, current: current);
      },
    );
  }

  /// Loads the hourly periods. On failure the old ones go, since the forecast
  /// beside them is new; the section says so and offers [retryHourly].
  Future<void> loadHourly(CoarseLocation location) async {
    final generation = _generation;
    state = state.copyWith(
      error: state.error,
      hourlyLoading: true,
      clearHourlyError: true,
    );
    final result = await _repository.getHourlyForecast(location);
    if (!_isCurrent(generation)) return;
    result.fold(
      (failure) => state = state.copyWith(
        error: state.error,
        clearHourly: true,
        hourlyLoading: false,
        hourlyError: failure,
      ),
      (hours) => state = state.copyWith(
        error: state.error,
        hourly: hours,
        hourlyLoading: false,
      ),
    );
  }

  /// The hourly section's Retry: one call, not a whole reload.
  Future<void> retryHourly() async {
    final location = _hourlyLocation;
    if (location != null && !state.hourlyLoading) await loadHourly(location);
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
