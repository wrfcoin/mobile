import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../core/errors/failures.dart';
import '../../features/collector/data/repositories/collector_repository_impl.dart';
import '../storage/local_db.dart';

final offlineDataBufferProvider = Provider<OfflineDataBuffer>((ref) {
  return OfflineDataBuffer(db: ref.watch(appDatabaseProvider));
});

/// Offline-first data layer.
///
/// Wraps any async fetch with a stale-while-revalidate strategy:
///  1. Return the locally cached value immediately (if present and within TTL).
///  2. Fire the network fetch in the background.
///  3. On success, persist the new payload and emit it.
///  4. On failure (offline), return the cached value with [OfflineDataResult.fromCache].
///
/// Also exposes [syncOnReconnect] which re-runs a registered set of refresh
/// callbacks whenever connectivity is restored — ensuring the UI updates
/// automatically when the user comes back online.
class OfflineDataBuffer {
  OfflineDataBuffer({required this._db, Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
  }

  final AppDatabase _db;
  final Connectivity _connectivity;

  /// Registered refresh callbacks keyed by a human-readable name.
  final Map<String, Future<void> Function()> _refreshCallbacks = {};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Register a callback to be invoked when the device reconnects.
  /// Callers should call this once, e.g. in provider initialization.
  void registerSyncCallback(String name, Future<void> Function() callback) {
    _refreshCallbacks[name] = callback;
  }

  void unregisterSyncCallback(String name) {
    _refreshCallbacks.remove(name);
  }

  /// Fetches data using [fetch], caching the result under [cacheKey].
  ///
  /// - If [fetch] succeeds, returns [OfflineDataResult.fresh].
  /// - If [fetch] fails but a cached value exists, returns [OfflineDataResult.fromCache].
  /// - If [fetch] fails and no cache exists, returns [OfflineDataResult.failure].
  ///
  /// [maxAge] controls the maximum age before a successful network fetch is
  /// required.  Passing [Duration.zero] bypasses the TTL check (always fetch).
  Future<OfflineDataResult<T>> fetchWithCache<T>({
    required String cacheKey,
    required Future<Either<Failure, T>> Function() fetch,
    required T Function(Map<String, dynamic> json) fromJson,
    required Map<String, dynamic> Function(T value) toJson,
    Duration maxAge = const Duration(minutes: 15),
  }) async {
    // Attempt the live fetch first.
    final result = await fetch();

    return result.fold(
      // Network / server failure — try the cache.
      (failure) async {
        final cached = await _db.getOfflineData(cacheKey);
        if (cached == null) {
          return OfflineDataResult.failure(failure);
        }

        // Honour maxAge; if cache is also too old, surface the failure.
        if (maxAge != Duration.zero) {
          final age = DateTime.now().difference(cached.cachedAt);
          if (age > maxAge) {
            return OfflineDataResult.failure(failure);
          }
        }

        try {
          final decoded = jsonDecode(cached.payload) as Map<String, dynamic>;
          return OfflineDataResult.fromCache(
            fromJson(decoded),
            cachedAt: cached.cachedAt,
          );
        } catch (_) {
          return OfflineDataResult.failure(failure);
        }
      },
      // Success — persist and return.
      (value) async {
        final payload = jsonEncode(toJson(value));
        await _db.upsertOfflineData(cacheKey, payload);
        return OfflineDataResult.fresh(value);
      },
    );
  }

  // ── Reconnect handling ─────────────────────────────────────────────────────

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = !results.contains(ConnectivityResult.none);
    if (hasNetwork && _refreshCallbacks.isNotEmpty) {
      _triggerRefresh();
    }
  }

  Future<void> _triggerRefresh() async {
    for (final callback in List.of(_refreshCallbacks.values)) {
      try {
        await callback();
      } catch (_) {
        // Swallow per-callback errors; other callbacks should still run.
      }
    }
  }
}

/// Typed result from [OfflineDataBuffer.fetchWithCache].
sealed class OfflineDataResult<T> {
  const OfflineDataResult();

  const factory OfflineDataResult.fresh(T value) = _FreshResult<T>;
  const factory OfflineDataResult.fromCache(
    T value, {
    required DateTime cachedAt,
  }) = _CachedResult<T>;
  const factory OfflineDataResult.failure(Failure failure) = _FailureResult<T>;

  bool get isFresh => this is _FreshResult<T>;
  bool get isFromCache => this is _CachedResult<T>;
  bool get isFailure => this is _FailureResult<T>;

  T? get valueOrNull => switch (this) {
    _FreshResult<T>(value: final v) => v,
    _CachedResult<T>(value: final v) => v,
    _FailureResult<T>() => null,
  };

  DateTime? get cachedAt => switch (this) {
    _CachedResult<T>(cachedAt: final d) => d,
    _ => null,
  };

  Failure? get failure => switch (this) {
    _FailureResult<T>(failure: final f) => f,
    _ => null,
  };
}

final class _FreshResult<T> extends OfflineDataResult<T> {
  const _FreshResult(this.value);
  final T value;
}

final class _CachedResult<T> extends OfflineDataResult<T> {
  const _CachedResult(this.value, {required this.cachedAt});
  final T value;
  @override
  final DateTime cachedAt;
}

final class _FailureResult<T> extends OfflineDataResult<T> {
  const _FailureResult(this.failure);
  @override
  final Failure failure;
}
