import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/feature_flags/feature_flags.dart';
import '../features/collector/data/repositories/collector_repository_impl.dart';
import '../services/storage/db_path_stub.dart'
    if (dart.library.io) '../services/storage/db_path.dart';
import '../services/storage/local_db.dart';
import '../services/observability/app_logger.dart';
import '../services/observability/crash_reporter.dart';

/// Builds the provider overrides the shipped app runs with.
///
/// Every provider that throws unless overridden and is reachable from the
/// app shell must be satisfied here (#317). Both main and the app-shell test
/// obtain these overrides through [createAppContainer], so a missing override
/// fails a test instead of shipping a gray screen.
///
/// [openDatabase] exists so tests can substitute an in-memory executor for
/// the on-disk database. [loadPreferences] substitutes platform I/O when
/// testing initialization failures; production uses both defaults.
Future<List<Override>> buildAppOverrides({
  QueryExecutor Function() openDatabase = openAppDatabase,
  Future<SharedPreferences> Function() loadPreferences =
      SharedPreferences.getInstance,
}) async {
  final prefs = await loadPreferences();

  return <Override>[
    sharedPreferencesProvider.overrideWithValue(prefs),
    // openAppDatabase() uses a native path API unavailable on web. On web the
    // provider remains unimplemented and the collector feature shows the
    // web-unavailable banner.
    if (!kIsWeb)
      appDatabaseProvider.overrideWithValue(AppDatabase(openDatabase())),
  ];
}

/// The container used by main and the real app-shell regression test (#319).
/// Bootstrap failures happen before container-backed global error handlers
/// exist, so record them explicitly with a reporter that needs no providers.
Future<ProviderContainer> createAppContainer({
  QueryExecutor Function() openDatabase = openAppDatabase,
  Future<SharedPreferences> Function() loadPreferences =
      SharedPreferences.getInstance,
  CrashReporter bootstrapReporter = const ConsoleCrashReporter(
    AppLogger(
      sinks: [ConsoleLogSink(verbose: kDebugMode)],
      verbose: kDebugMode,
    ),
  ),
}) async {
  try {
    final overrides = await buildAppOverrides(
      openDatabase: openDatabase,
      loadPreferences: loadPreferences,
    );
    return ProviderContainer(overrides: overrides);
  } catch (error, stackTrace) {
    await bootstrapReporter.recordError(
      error,
      stackTrace,
      reason: 'app_bootstrap',
      fatal: true,
    );
    rethrow;
  }
}
