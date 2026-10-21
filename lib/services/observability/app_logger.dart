import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'telemetry_redactor.dart';

enum AppLogLevel { debug, info, warning, error }

class AppLogEntry {
  final DateTime timestamp;
  final AppLogLevel level;
  final String event;
  final Map<String, dynamic> fields;

  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.event,
    required this.fields,
  });
}

abstract class LogSink {
  void write(AppLogEntry entry);
}

class ConsoleLogSink implements LogSink {
  const ConsoleLogSink({required this.verbose});

  final bool verbose;

  @override
  void write(AppLogEntry entry) {
    if (!verbose && entry.level == AppLogLevel.debug) return;

    developer.log(
      jsonEncode(<String, dynamic>{
        'ts': entry.timestamp.toIso8601String(),
        'level': entry.level.name,
        'event': entry.event,
        'fields': entry.fields,
      }),
      name: 'wrfcoin.mobile',
      level: _developerLevel(entry.level),
    );
  }

  int _developerLevel(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.debug:
        return 500;
      case AppLogLevel.info:
        return 800;
      case AppLogLevel.warning:
        return 900;
      case AppLogLevel.error:
        return 1000;
    }
  }
}

class MemoryLogSink implements LogSink {
  final List<AppLogEntry> entries = <AppLogEntry>[];

  @override
  void write(AppLogEntry entry) {
    entries.add(entry);
  }
}

class AppLogger {
  final List<LogSink> _sinks;
  final bool _verbose;

  const AppLogger({required this._sinks, required this._verbose});

  void debug(String event, {Map<String, dynamic>? fields}) {
    _log(AppLogLevel.debug, event, fields: fields);
  }

  void info(String event, {Map<String, dynamic>? fields}) {
    _log(AppLogLevel.info, event, fields: fields);
  }

  void warning(String event, {Map<String, dynamic>? fields}) {
    _log(AppLogLevel.warning, event, fields: fields);
  }

  void error(String event, {Map<String, dynamic>? fields}) {
    _log(AppLogLevel.error, event, fields: fields);
  }

  void _log(AppLogLevel level, String event, {Map<String, dynamic>? fields}) {
    if (!_verbose && level == AppLogLevel.debug) return;

    final entry = AppLogEntry(
      timestamp: DateTime.now(),
      level: level,
      event: event,
      fields: TelemetryRedactor.redactMap(fields ?? const <String, dynamic>{}),
    );

    for (final sink in _sinks) {
      sink.write(entry);
    }
  }
}

final logSinksProvider = Provider<List<LogSink>>((ref) {
  return <LogSink>[ConsoleLogSink(verbose: kDebugMode)];
});

final appLoggerProvider = Provider<AppLogger>((ref) {
  final verbose = kDebugMode || const bool.fromEnvironment('LOG_VERBOSE');
  return AppLogger(sinks: ref.watch(logSinksProvider), verbose: verbose);
});
