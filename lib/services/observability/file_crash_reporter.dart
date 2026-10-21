import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'crash_report_store.dart';
import 'telemetry_redactor.dart';

/// Device-local ring. Writes, pruning, reads and deletion share one queue.
/// Temporary writes are renamed atomically; only this reporter's files are removed.
class FileCrashReporter implements CrashReportStore {
  FileCrashReporter(
    this.directory, {
    this.maxReports = 50,
    this.appVersion = 'unavailable',
    this.platform = 'unavailable',
  }) {
    if (maxReports < 1 || maxReports > 500) {
      throw ArgumentError.value(maxReports, 'maxReports', 'must be 1..500');
    }
  }

  final Directory directory;
  final int maxReports;
  final String appVersion;
  final String platform;
  static const maxReportBytes = 32 * 1024;
  static final _ownedName = RegExp(r'^crash-[0-9]+\.json$');
  static final _pendingName = RegExp(r'^crash-[0-9]+\.json\.pending$');
  Future<void> _pending = Future.value();
  int _lastId = 0;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<List<File>> _files() async {
    if (!await directory.exists()) return [];
    final files = <File>[];
    await for (final entry in directory.list(followLinks: false)) {
      // A process terminated mid-write can leave a partial file. No write is
      // in flight here because callers share the operation queue.
      if (entry is File && _pendingName.hasMatch(entry.uri.pathSegments.last)) {
        await entry.delete();
        continue;
      }
      if (entry is File && _ownedName.hasMatch(entry.uri.pathSegments.last)) {
        files.add(entry);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static dynamic _omitSecrets(dynamic value) {
    if (value is Map) {
      return {
        for (final e in value.entries)
          if (e.value != '[REDACTED]' && e.key != '[REDACTED]')
            e.key.toString(): _omitSecrets(e.value),
      };
    }
    if (value is List) return value.map(_omitSecrets).toList();
    if (value == null ||
        value is String ||
        value is bool ||
        (value is num && value.isFinite)) {
      return value;
    }
    return '[UNSERIALIZABLE]';
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    bool fatal = false,
    Map<String, dynamic> context = const {},
  }) => _enqueue(() async {
    // All free text and nested context go through the shared redactor before disk.
    final report = TelemetryRedactor.redactMap({
      'reason': reason,
      'fatal': fatal,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
      'context': context,
      'appVersion': appVersion,
      'platform': platform,
    });
    report['context'] = _omitSecrets(report['context']);
    var encoded = utf8.encode(jsonEncode(report));
    if (encoded.length > maxReportBytes) {
      // Keep structural diagnostics while bounding even adversarial giant reports.
      encoded = utf8.encode(
        jsonEncode({
          'reason': 'report_too_large',
          'fatal': fatal,
          'error': error.runtimeType.toString(),
          'stackTrace': '[TRUNCATED]',
          'context': {'truncated': true},
          'appVersion': report['appVersion'],
          'platform': report['platform'],
        }),
      );
    }
    // Also bound caller-supplied version/platform metadata in the fallback.
    if (encoded.length > maxReportBytes) {
      encoded = utf8.encode(
        jsonEncode({
          'reason': 'report_too_large',
          'fatal': fatal,
          'error': '[TRUNCATED]',
          'stackTrace': '[TRUNCATED]',
          'context': {'truncated': true},
          'appVersion': 'unavailable',
          'platform': 'unavailable',
        }),
      );
    }
    await directory.create(recursive: true);
    _lastId = math.max(
      DateTime.now().toUtc().microsecondsSinceEpoch,
      _lastId + 1,
    );
    final target = File('${directory.path}/crash-$_lastId.json');
    final temporary = File('${target.path}.pending');
    try {
      await temporary.writeAsBytes(encoded, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    final files = await _files();
    for (final file in files.take(math.max(0, files.length - maxReports))) {
      await file.delete();
    }
  });

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

  Future<List<File>> list() => _enqueue(_files);

  @override
  Future<int> count() => _enqueue(() async => (await _files()).length);

  @override
  Future<List<XFile>> exportFiles() => _enqueue(() async {
    // A byte snapshot survives subsequent pruning or Delete while the OS sheet is open.
    return [
      for (final file in await _files())
        XFile.fromData(
          await file.readAsBytes(),
          mimeType: 'application/json',
          name: file.uri.pathSegments.last,
        ),
    ];
  });

  @override
  Future<void> clear() => _enqueue(() async {
    for (final file in await _files()) {
      await file.delete();
    }
  });
}
