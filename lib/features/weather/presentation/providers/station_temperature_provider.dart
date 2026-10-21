import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_handoff.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/station_temperature_remote_datasource.dart';
import '../../data/weather_location_resolver.dart';
import '../../domain/models/station_temperature.dart';
import '../../domain/models/weather_narrative.dart';
import 'weather_narratives_provider.dart';

enum StationTemperatureStatus {
  /// Nothing is shown: not signed in, no location, backgrounded, or the
  /// backend route is not deployed (404/501).
  hidden,
  loading,

  /// A real answer with no temperature for this cell.
  empty,
  ready,

  /// A failed read (5xx, network): a quiet note, not an error screen.
  unavailable,
}

class StationTemperatureState {
  const StationTemperatureState({
    this.status = StationTemperatureStatus.hidden,
    this.narratives = const [],
  });

  final StationTemperatureStatus status;
  final List<WeatherNarrative> narratives;
}

/// Whether the user has a CURRENT session: the handoff is clear (no sign-out,
/// expiry or rejection) and an access token is stored. It reads storage only:
/// it never starts a login, prompts, or sends a request.
final stationTemperatureSignedInProvider = Provider<Future<bool> Function()>((
  ref,
) {
  final keys = ref.watch(keyManagerProvider);
  return () async =>
      !ref.read(authHandoffControllerProvider).requiresWalletConnect &&
      (await keys.getAuthToken()) != null;
});

/// Whether the app is in the foreground. No request is made otherwise.
final stationTemperatureForegroundProvider = Provider<bool Function()>((_) {
  return () {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  };
});

/// Tells the notifier when the app leaves the foreground.
class _BackgroundObserver with WidgetsBindingObserver {
  _BackgroundObserver(this.onBackground);
  final void Function() onBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) onBackground();
  }
}

class StationTemperatureNotifier extends Notifier<StationTemperatureState> {
  int _generation = 0;
  WeatherLocationRequest? _pendingLocation;
  CancelToken _token = CancelToken();

  /// Cancels the location wait and any in-flight read, and makes every pending
  /// continuation stale. The read also has no automatic retry, so nothing is
  /// re-sent after this.
  void _cancelReads() {
    _generation++;
    _pendingLocation?.cancel();
    _pendingLocation = null;
    if (!_token.isCancelled) _token.cancel('station temperature not allowed');
    _token = CancelToken();
  }

  @override
  StationTemperatureState build() {
    final observer = _BackgroundObserver(_cancelReads);
    try {
      WidgetsBinding.instance.addObserver(observer);
    } catch (_) {
      // No binding (a plain unit test): the foreground provider still gates every run.
    }
    ref.onDispose(() {
      try {
        WidgetsBinding.instance.removeObserver(observer);
      } catch (_) {}
      _cancelReads();
    });
    // Sign-out, expiry or rejection: stop what is pending and hide the section.
    ref.listen(authHandoffControllerProvider, (_, handoff) {
      if (handoff.requiresWalletConnect) {
        _cancelReads();
        state = const StationTemperatureState();
      }
    });
    Future.microtask(load);
    return const StationTemperatureState();
  }

  /// First load: hides the section when nothing can be asked.
  Future<void> load() => _run(initial: true);

  /// Re-reads; while backgrounded it makes no request and keeps the state.
  Future<void> refresh() => _run(initial: false);

  Future<void> _run({required bool initial}) async {
    final generation = ++_generation;
    bool current() => ref.mounted && generation == _generation;

    final foreground = ref.read(stationTemperatureForegroundProvider);
    if (!foreground()) {
      if (initial) state = const StationTemperatureState();
      return;
    }
    if (!await ref.read(stationTemperatureSignedInProvider)()) {
      if (!current()) return;
      state = const StationTemperatureState();
      return;
    }
    if (!current()) return;

    _pendingLocation?.cancel();
    final request = _pendingLocation = ref
        .read(weatherLocationResolverProvider)
        .request();
    final located = await request.result;
    if (!current()) return;
    _pendingLocation = null;
    final cell = located.location;
    // The location wait can span a backgrounding or a sign-out: re-check both
    // (and that this run is still the current one) immediately before the request.
    if (cell == null || !foreground()) {
      if (initial || cell == null) state = const StationTemperatureState();
      return;
    }
    if (!await ref.read(stationTemperatureSignedInProvider)()) {
      if (current()) state = const StationTemperatureState();
      return;
    }
    if (!current() || !foreground()) return;

    final token = _token;
    final result = await ref
        .read(stationTemperatureDataSourceProvider)
        .fetch(cell, cancelToken: token);
    if (!current() || token.isCancelled) return;
    switch (result.kind) {
      case StationTemperatureFetchKind.hidden:
        state = const StationTemperatureState();
      case StationTemperatureFetchKind.unavailable:
        state = const StationTemperatureState(
          status: StationTemperatureStatus.unavailable,
        );
      case StationTemperatureFetchKind.data:
        final history = result.history!;
        final narratives = buildStationTemperatureNarratives(
          history,
          ref.read(weatherNarrativesClockProvider)(),
        );
        // Completed days only: no narrative means nothing recent to say.
        state = narratives.isEmpty
            ? const StationTemperatureState(
                status: StationTemperatureStatus.empty,
              )
            : StationTemperatureState(
                status: StationTemperatureStatus.ready,
                narratives: narratives,
              );
    }
  }
}

final stationTemperatureProvider =
    NotifierProvider<StationTemperatureNotifier, StationTemperatureState>(
      StationTemperatureNotifier.new,
    );
