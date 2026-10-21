import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../data/models/forecast_detail_model.dart';
import '../../data/repositories/weather_repository_impl.dart';
import '../../data/weather_location_resolver.dart';
import '../../domain/models/coarse_location.dart';

class ForecastDetailState {
  final ForecastDetail? detail;
  final bool loading;
  final Failure? error;

  /// Why there is no usable location; null when there is one. No request
  /// was made without one.
  final LocationUnavailableReason? locationUnavailable;

  bool get locationNeeded => locationUnavailable != null;

  const ForecastDetailState({
    this.detail,
    this.loading = false,
    this.error,
    this.locationUnavailable,
  });

  ForecastDetailState copyWith({
    ForecastDetail? detail,
    bool? loading,
    Failure? error,
    bool clearLocationUnavailable = false,
  }) {
    return ForecastDetailState(
      detail: detail ?? this.detail,
      loading: loading ?? this.loading,
      error: error,
      // Only location resolution changes it; a load result never does
      // (mobile#326 item 1) — except via the explicit clear flag, set once
      // loadLocal() has actually resolved a location (review round 1 P1,
      // #330): otherwise a later successful load after a grant stayed
      // stuck behind "Allow location" forever.
      locationUnavailable: clearLocationUnavailable
          ? null
          : locationUnavailable,
    );
  }
}

class ForecastDetailNotifier extends Notifier<ForecastDetailState> {
  late WeatherRepository _repository;
  late WeatherLocationResolver _locationResolver;
  WeatherLocationRequest? _pendingLocation;

  /// Bumped by every [loadLocal]. A result from an older load is dropped, so
  /// a late answer cannot overwrite a newer state, e.g. the no-location
  /// state after permission is revoked (mobile#326 item 1, as in
  /// `WeatherNotifier`).
  int _generation = 0;

  @override
  ForecastDetailState build() {
    _repository = ref.watch(weatherRepositoryProvider);
    _locationResolver = ref.watch(weatherLocationResolverProvider);
    ref.onDispose(() => _pendingLocation?.cancel());
    return const ForecastDetailState();
  }

  /// Loads the detail for the device's rounded location; without one, makes
  /// no request and sets [ForecastDetailState.locationUnavailable].
  Future<void> loadLocal() async {
    final generation = ++_generation;
    state = state.copyWith(loading: true, error: null);
    _pendingLocation?.cancel();
    final request = _pendingLocation = _locationResolver.request();
    final result = await request.result;
    if (!_isCurrent(generation)) return;
    _pendingLocation = null;
    final location = result.location;
    if (location == null) {
      state = ForecastDetailState(locationUnavailable: result.reason);
      return;
    }
    // A location resolved: clear any stale locationUnavailable before
    // loading, so a grant-then-success no longer stays behind "Allow
    // location".
    state = state.copyWith(clearLocationUnavailable: true);
    await load(location);
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  Future<void> load(CoarseLocation location) async {
    final generation = _generation;
    state = state.copyWith(loading: true, error: null);

    final result = await _repository.getForecastDetail(location);
    if (!_isCurrent(generation)) return;
    result.fold(
      (failure) => state = state.copyWith(loading: false, error: failure),
      (detail) => state = state.copyWith(loading: false, detail: detail),
    );
  }
}

final forecastDetailProvider =
    NotifierProvider.autoDispose<ForecastDetailNotifier, ForecastDetailState>(
      ForecastDetailNotifier.new,
    );
