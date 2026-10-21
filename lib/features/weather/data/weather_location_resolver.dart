import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/models/coarse_location.dart';

final weatherLocationResolverProvider = Provider<WeatherLocationResolver>((
  ref,
) {
  return const WeatherLocationResolver();
});

/// Why the weather screens have no location. Each reason gets its own card
/// and its own action (mobile#328).
enum LocationUnavailableReason {
  /// Permission not granted yet; Android can still show its dialog.
  permissionDenied,

  /// Permission denied for good: Android will not show the dialog again, so
  /// only the app's settings page can grant it.
  permissionBlocked,

  /// Permission granted, but the device's location services are off.
  servicesOff,

  /// Permission granted and location on, but neither a fresh fix nor a
  /// last-known position was available.
  noFix,
}

/// The outcome of a resolution: a rounded [location], or the [reason] there
/// is none.
class WeatherLocationResult {
  const WeatherLocationResult.located(CoarseLocation this.location)
    : reason = null;

  const WeatherLocationResult.unavailable(LocationUnavailableReason this.reason)
    : location = null;

  final CoarseLocation? location;
  final LocationUnavailableReason? reason;

  @override
  String toString() => location != null
      ? 'WeatherLocationResult($location)'
      : 'WeatherLocationResult(${reason!.name})';
}

/// Resolves the position the weather screens are keyed by.
///
/// Uses location only when permission is already granted: it never asks for
/// permission itself (the "Allow location" button does, on an explicit tap).
/// Without a location it returns the reason, and callers make no request.
class WeatherLocationResolver {
  const WeatherLocationResolver();

  /// Bound on the position fix. Keep it: only Geolocator's `timeLimit` makes
  /// the Android plugin cancel the native request (cancelGetCurrentPosition,
  /// removeLocationUpdates). Without it the phone keeps location active after
  /// the screen gives up or goes away.
  static const _fixTimeout = Duration(seconds: 15);

  /// Upper bound for the whole resolution, so a platform call without its own
  /// timeout (the permission check) cannot leave the screen loading forever.
  static const _overallTimeout = Duration(seconds: 20);

  /// Balanced power (Android PRIORITY_BALANCED_POWER_ACCURACY). Low power
  /// never turns on a location source and timed out on a real phone with no
  /// cached fix (mobile#328). The fix is rounded to 0.1° anyway, so this is
  /// about getting a fix at all, not about precision.
  static const fixAccuracy = LocationAccuracy.medium;

  /// Starts a resolution bounded by the overall timeout. The owner cancels it
  /// on dispose, so its timer never outlives the screen.
  WeatherLocationRequest request() {
    final completer = Completer<WeatherLocationResult>();
    final timer = Timer(_overallTimeout, () {
      if (!completer.isCompleted) completer.complete(_noFix);
    });
    resolve().then((result) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });
    return WeatherLocationRequest._(completer, timer);
  }

  static const _noFix = WeatherLocationResult.unavailable(
    LocationUnavailableReason.noFix,
  );

  /// The resolution itself, without the overall timeout. Never throws.
  Future<WeatherLocationResult> resolve() async {
    try {
      final initial = await _permissionAndServicesGate();
      if (initial != null) return initial;

      var position = await _freshFix();
      if (position == null) {
        // The fresh fix can wait up to the full 15s timeLimit (or fail
        // fast). Re-check permission and services immediately before
        // falling back to the last-known position: a revoke during that
        // wait must not let a cached position through (mobile#324
        // invariant; PR #329 review round 1 P1).
        final beforeLastKnown = await _permissionAndServicesGate();
        if (beforeLastKnown != null) return beforeLastKnown;
        position = await _lastKnown();
      }
      if (position == null) return _noFix;

      // Re-check once more immediately before returning any location: a
      // revoke that lands after the platform call returns but before we
      // act on it must not be allowed through on the fresh-fix path
      // either.
      final beforeReturn = await _permissionAndServicesGate();
      if (beforeReturn != null) return beforeReturn;

      return WeatherLocationResult.located(
        CoarseLocation.round(position.latitude, position.longitude),
      );
    } catch (e) {
      debugPrint('Weather location unavailable: ${e.runtimeType}');
      return _noFix;
    }
  }

  /// Checks permission and location-service state. Returns the matching
  /// unavailable result if either is missing, else null.
  Future<WeatherLocationResult?> _permissionAndServicesGate() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      return const WeatherLocationResult.unavailable(
        LocationUnavailableReason.permissionBlocked,
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return const WeatherLocationResult.unavailable(
        LocationUnavailableReason.permissionDenied,
      );
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const WeatherLocationResult.unavailable(
        LocationUnavailableReason.servicesOff,
      );
    }
    return null;
  }

  Future<Position?> _freshFix() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: fixAccuracy,
          timeLimit: _fixTimeout,
        ),
      );
    } catch (e) {
      debugPrint('Weather fresh fix unavailable: ${e.runtimeType}');
      return null;
    }
  }

  /// The platform's cached position. At 0.1° (about 11 km) an older fix is
  /// still the right forecast cell.
  Future<Position?> _lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      debugPrint('Weather last-known position unavailable: ${e.runtimeType}');
      return null;
    }
  }
}

/// A running [WeatherLocationResolver.request].
class WeatherLocationRequest {
  WeatherLocationRequest._(this._completer, this._timer);

  final Completer<WeatherLocationResult> _completer;
  final Timer _timer;

  /// The rounded location or the reason there is none. The overall timeout
  /// and [cancel] give [LocationUnavailableReason.noFix].
  Future<WeatherLocationResult> get result => _completer.future;

  /// Stops the timeout timer and completes [result] with no fix.
  void cancel() {
    _timer.cancel();
    if (!_completer.isCompleted) {
      _completer.complete(WeatherLocationResolver._noFix);
    }
  }
}
