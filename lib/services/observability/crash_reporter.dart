import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_logger.dart';
import 'crash_report_store.dart';
import 'telemetry_redactor.dart';

class CrashReport {
  final Object error;
  final StackTrace stackTrace;
  final String reason;
  final bool fatal;
  final Map<String, dynamic> context;

  const CrashReport({
    required this.error,
    required this.stackTrace,
    required this.reason,
    required this.fatal,
    this.context = const <String, dynamic>{},
  });
}

abstract class CrashReporter {
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    bool fatal = false,
    Map<String, dynamic> context = const <String, dynamic>{},
  });

  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    bool fatal = false,
    Map<String, dynamic> context = const <String, dynamic>{},
  });
}

class ConsoleCrashReporter implements CrashReporter {
  final AppLogger _logger;

  const ConsoleCrashReporter(this._logger);

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    bool fatal = false,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) async {
    _logger.error(
      'app_crash',
      fields: <String, dynamic>{
        'reason': reason,
        'fatal': fatal,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
        ...context,
      },
    );
  }

  @override
  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    bool fatal = false,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) {
    return recordError(
      details.exception,
      details.stack ?? StackTrace.current,
      reason: 'flutter_error',
      fatal: fatal,
      context: <String, dynamic>{'library': details.library, ...context},
    );
  }
}

class MemoryCrashReporter implements CrashReporter {
  final List<CrashReport> reports = <CrashReport>[];

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    bool fatal = false,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) async {
    final redactedContext = TelemetryRedactor.redactMap(context);
    reports.add(
      CrashReport(
        error: error,
        stackTrace: stackTrace,
        reason: reason,
        fatal: fatal,
        context: redactedContext,
      ),
    );
  }

  @override
  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    bool fatal = false,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) {
    return recordError(
      details.exception,
      details.stack ?? StackTrace.current,
      reason: 'flutter_error',
      fatal: fatal,
      context: context,
    );
  }
}

final crashReporterProvider = Provider<CrashReporter>((ref) {
  return CompositeCrashReporter([
    ConsoleCrashReporter(ref.watch(appLoggerProvider)),
    DeferredCrashReporter(
      ref
          .watch(localCrashReportStoreProvider.future)
          .catchError((Object _) => null),
    ),
  ]);
});

/// A failure of one sink must not stop the other or recurse into global handlers.
class CompositeCrashReporter implements CrashReporter {
  const CompositeCrashReporter(this.reporters);
  final List<CrashReporter> reporters;

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    bool fatal = false,
    Map<String, dynamic> context = const {},
  }) async {
    for (final reporter in reporters) {
      try {
        await reporter.recordError(
          error,
          stackTrace,
          reason: reason,
          fatal: fatal,
          context: context,
        );
      } catch (_) {
        debugPrint('Crash report storage unavailable');
      }
    }
  }

  @override
  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    bool fatal = false,
    Map<String, dynamic> context = const {},
  }) => recordError(
    details.exception,
    details.stack ?? StackTrace.current,
    reason: 'flutter_error',
    fatal: fatal,
    context: {'library': details.library, ...context},
  );
}

class DeferredCrashReporter implements CrashReporter {
  const DeferredCrashReporter(this.reporter);
  final Future<CrashReporter?> reporter;

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    bool fatal = false,
    Map<String, dynamic> context = const {},
  }) async {
    final sink = await reporter;
    await sink?.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
      context: context,
    );
  }

  @override
  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    bool fatal = false,
    Map<String, dynamic> context = const {},
  }) async => (await reporter)?.recordFlutterError(
    details,
    fatal: fatal,
    context: context,
  );
}

void configureGlobalErrorHandling(CrashReporter reporter) {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(reporter.recordFlutterError(details, fatal: true));
    if (previousOnError != null) {
      previousOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(
      reporter.recordError(
        error,
        stackTrace,
        reason: 'platform_dispatcher',
        fatal: true,
      ),
    );
    return true;
  };
}

Future<void> runWithCrashReporting(
  CrashReporter reporter,
  Future<void> Function() body,
) async {
  final completer = Completer<void>();

  runZonedGuarded(
    () async {
      try {
        await body();
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    },
    (error, stackTrace) async {
      await reporter.recordError(
        error,
        stackTrace,
        reason: 'run_zoned_guarded',
        fatal: true,
      );
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
  );

  await completer.future;
}
