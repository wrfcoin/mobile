import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../data/models/wrf_forecast_model.dart';
import '../../data/repositories/weather_repository_impl.dart';
import '../../data/weather_location_resolver.dart';
import '../../domain/models/coarse_location.dart';

/// Immutable UI state for the WRF forecast feature.
///
/// [data] only ever holds a server response. When the endpoint fails the
/// state is [unavailable]; any previous real response is kept, but nothing
/// is generated on the device (mobile#269).
class WrfForecastState {
  final WrfForecastModel? data;
  final bool loading;
  final Failure? error;

  /// The last fetch failed. With no [data], the UI shows an explicit
  /// unavailable state instead of a chart.
  final bool unavailable;
  final String? unavailableReason;

  const WrfForecastState({
    this.data,
    this.loading = false,
    this.error,
    this.unavailable = false,
    this.unavailableReason,
  });

  WrfForecastState copyWith({
    WrfForecastModel? data,
    bool? loading,
    Failure? error,
  }) {
    return WrfForecastState(
      data: data ?? this.data,
      loading: loading ?? this.loading,
      error: error,
      unavailable: unavailable,
      unavailableReason: unavailableReason,
    );
  }
}

/// Manages WRF forecast data with a 5-minute auto-refresh cycle.
class WrfForecastNotifier extends Notifier<WrfForecastState> {
  late WeatherRepository _repository;
  late WeatherLocationResolver _locationResolver;

  Timer? _refreshTimer;
  WeatherLocationRequest? _pendingLocation;
  int _generation = 0;
  bool _refreshing = false;

  static const _refreshInterval = Duration(minutes: 5);

  @override
  WrfForecastState build() {
    _repository = ref.watch(weatherRepositoryProvider);
    _locationResolver = ref.watch(weatherLocationResolverProvider);
    _refreshing = false;
    ref.onDispose(() {
      _generation++;
      _refreshTimer?.cancel();
      _pendingLocation?.cancel();
    });
    return const WrfForecastState();
  }

  /// Load the WRF forecast for [location] and start the 5-minute refresh timer.
  ///
  /// Safe to call multiple times — resets the timer on each call.
  Future<void> loadWrfForecast(CoarseLocation location) async {
    final generation = ++_generation;
    _pendingLocation?.cancel();
    _pendingLocation = null;
    _refreshing = true;

    // Cancel any existing timer before starting a fresh one.
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      unawaited(_refreshLocal());
    });

    try {
      await _fetchAndUpdate(location, generation);
    } finally {
      if (_isCurrent(generation)) _refreshing = false;
    }
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  /// A timer has no permission to reuse a previously supplied location.
  /// Resolve again without requesting permission, and stop if unavailable.
  Future<void> _refreshLocal() async {
    if (!ref.mounted || _refreshing) return;
    final generation = ++_generation;
    _refreshing = true;
    try {
      final request = _pendingLocation = _locationResolver.request();
      final result = await request.result;
      if (!_isCurrent(generation)) return;
      _pendingLocation = null;
      final location = result.location;
      if (location == null) {
        _refreshTimer?.cancel();
        state = WrfForecastState(
          unavailable: true,
          unavailableReason: switch (result.reason) {
            LocationUnavailableReason.permissionDenied ||
            LocationUnavailableReason.permissionBlocked =>
              'Allow location to refresh the forecast.',
            LocationUnavailableReason.servicesOff =>
              'Turn on Location to refresh the forecast.',
            _ => 'Could not get a location fix. Try again.',
          },
        );
        return;
      }
      await _fetchAndUpdate(location, generation);
    } finally {
      if (_isCurrent(generation)) _refreshing = false;
    }
  }

  Future<void> _fetchAndUpdate(CoarseLocation location, int generation) async {
    if (!_isCurrent(generation)) return;
    state = state.copyWith(loading: true, error: null);

    final result = await _repository.getWrfForecast(location);
    if (!_isCurrent(generation)) return;
    result.fold(
      (failure) {
        // Keep the previous real response, if any; never substitute
        // device-generated numbers.
        state = WrfForecastState(
          data: state.data,
          loading: false,
          error: failure,
          unavailable: true,
          unavailableReason: failure.message,
        );
      },
      (forecast) {
        state = WrfForecastState(data: forecast, loading: false);
      },
    );
  }
}

final wrfForecastProvider =
    NotifierProvider.autoDispose<WrfForecastNotifier, WrfForecastState>(
      WrfForecastNotifier.new,
    );
