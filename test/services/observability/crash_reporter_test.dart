import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';
import 'package:wrfcoin_mobile/services/observability/crash_reporter.dart';

void main() {
  test('runWithCrashReporting reports uncaught zone errors', () async {
    final reporter = MemoryCrashReporter();

    await runWithCrashReporting(reporter, () async {
      throw StateError('boom');
    });

    expect(reporter.reports, hasLength(1));
    expect(reporter.reports.single.reason, 'run_zoned_guarded');
    expect(reporter.reports.single.fatal, isTrue);
    expect(reporter.reports.single.error, isA<StateError>());
  });

  test('console crash reporter redacts sensitive crash fields', () async {
    final sink = MemoryLogSink();
    final logger = AppLogger(sinks: <LogSink>[sink], verbose: true);
    final reporter = ConsoleCrashReporter(logger);

    await reporter.recordError(
      StateError('send failed for wrf1234567890abcdef'),
      StackTrace.fromString(
        'frame 0 transfer 0x1234567890abcdef1234567890abcdef12345678',
      ),
      reason: 'tx_failure',
      fatal: true,
      context: <String, dynamic>{
        'details':
            'mnemonic abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        'safeValue': 'network timeout',
      },
    );

    expect(sink.entries, hasLength(1));
    final entry = sink.entries.single;
    expect(entry.event, 'app_crash');
    expect(entry.fields['error'], isNot(contains('wrf1234567890abcdef')));
    expect(
      entry.fields['stackTrace'],
      isNot(contains('0x1234567890abcdef1234567890abcdef12345678')),
    );
    expect(entry.fields['details'], '[REDACTED]');
    expect(entry.fields['safeValue'], 'network timeout');
  });

  test('memory crash reporter stores redacted context', () async {
    final reporter = MemoryCrashReporter();

    await reporter.recordError(
      StateError('boom'),
      StackTrace.current,
      reason: 'test',
      context: <String, dynamic>{'note': 'wallet wrf1234567890abcdef'},
    );

    expect(reporter.reports, hasLength(1));
    expect(
      reporter.reports.single.context['note'],
      isNot(contains('wrf1234567890abcdef')),
    );
    expect(reporter.reports.single.context['note'], contains('[REDACTED]'));
  });
}
