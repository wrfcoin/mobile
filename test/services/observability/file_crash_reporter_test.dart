import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';
import 'package:wrfcoin_mobile/services/observability/crash_reporter.dart';
import 'package:wrfcoin_mobile/services/observability/crash_report_store.dart';
import 'package:wrfcoin_mobile/services/observability/file_crash_reporter.dart';
import 'package:wrfcoin_mobile/services/observability/crash_report_store_platform_stub.dart'
    as web;

void main() {
  late Directory dir;
  late FileCrashReporter reporter;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sol-a-crash-test-');
    reporter = FileCrashReporter(
      dir,
      maxReports: 3,
      appVersion: 'test-version',
      platform: 'test-platform',
    );
  });
  tearDown(() async => dir.delete(recursive: true));

  Future<void> record(int n) => reporter.recordError(
    StateError('failure $n'),
    StackTrace.current,
    reason: 'test_$n',
  );

  test('one atomic JSON file per report with bounded metadata', () async {
    await record(1);
    await record(2);
    final files = await reporter.list();
    expect(files, hasLength(2));
    final body = jsonDecode(await files.first.readAsString());
    expect(body, containsPair('reason', 'test_1'));
    expect(body, containsPair('appVersion', 'test-version'));
    expect(body, containsPair('platform', 'test-platform'));
    expect(body, containsPair('fatal', false));
    expect(await dir.list().length, 2, reason: 'no leftover temporary writes');
  });

  test('no secret values or sensitive context keys reach any persisted field', () async {
    const mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    final privateKey = 'ab' * 32;
    final address = '0x${'cd' * 20}';
    const jwt =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.longpayloadsegment123.longsignature987';
    await reporter.recordError(
      StateError('backup: $mnemonic; key $privateKey'),
      StackTrace.fromString(
        'wallet $address; Authorization: Bearer test-secret-123; lat=44.98765; coordinates 449876.5e-4,-932654.3e-4',
      ),
      reason: 'failure $jwt',
      context: {
        'mnemonic': mnemonic,
        'privateKey': privateKey,
        'jwtToken': jwt,
        'signature': 'ff' * 64,
        'password': 'password-sentinel',
        'apiKey': 'apikey-sentinel',
        'nested': {'note': 'backup: $mnemonic', 'latitude': 44.98765},
        'list': [
          {'detail': 'wallet $address', 'secret': 'secret-sentinel'},
        ],
        address: 'safe',
        'safe': 'offline timeout',
      },
    );
    final raw = await (await reporter.list()).single.readAsString();
    for (final secret in [
      mnemonic,
      privateKey,
      address,
      jwt,
      'ff' * 64,
      '44.98765',
      '449876.5e-4',
      '-932654.3e-4',
      'test-secret-123',
      'password-sentinel',
      'apikey-sentinel',
      'secret-sentinel',
    ]) {
      expect(raw, isNot(contains(secret)), reason: secret.substring(0, 6));
    }
    final body = jsonDecode(raw);
    expect(body['context'], isNot(contains('mnemonic')));
    expect(body['context'], isNot(contains('privateKey')));
    expect(body['context'], isNot(contains('signature')));
    expect(body['context']['safe'], 'offline timeout');
  });

  test('concurrent reports prune the oldest to the ring bound', () async {
    await Future.wait(List.generate(12, record));
    final files = await reporter.list();
    expect(files, hasLength(3));
    expect(
      await Future.wait(
        files.map((f) async => jsonDecode(await f.readAsString())['reason']),
      ),
      ['test_9', 'test_10', 'test_11'],
    );
  });

  test(
    'clear and writes are serialized, leaving only the later report',
    () async {
      final first = record(1);
      final clear = reporter.clear();
      final last = record(2);
      await Future.wait([first, clear, last]);
      expect(await reporter.count(), 1);
      expect(
        jsonDecode(
          await (await reporter.list()).single.readAsString(),
        )['reason'],
        'test_2',
      );
      await reporter.clear();
      expect(await reporter.count(), 0);
    },
  );

  test(
    'export snapshots survive clear and never include unrelated files or links',
    () async {
      await record(1);
      final unrelated = File('${dir.path}/notes.txt');
      await unrelated.writeAsString('unrelated');
      await Link('${dir.path}/crash-1.json').create(unrelated.path);
      final files = await reporter.exportFiles();
      expect(files, hasLength(1));
      await reporter.clear();
      expect(jsonDecode(await files.single.readAsString())['reason'], 'test_1');
      expect(await unrelated.exists(), isTrue);
      expect(await Link('${dir.path}/crash-1.json').exists(), isTrue);
      expect(await reporter.count(), 0);
    },
  );

  test('giant report is bounded and remains valid JSON', () async {
    await reporter.recordError(
      StateError('x' * 100000),
      StackTrace.current,
      reason: 'huge',
    );
    final bytes = await (await reporter.list()).single.readAsBytes();
    expect(bytes.length, lessThanOrEqualTo(FileCrashReporter.maxReportBytes));
    expect(
      jsonDecode(utf8.decode(bytes)),
      containsPair('reason', 'report_too_large'),
    );
  });

  test('non-JSON context values do not discard the crash', () async {
    await reporter.recordError(
      StateError('controlled'),
      StackTrace.current,
      reason: 'test',
      context: {'object': Object(), 'number': double.nan},
    );
    final body = jsonDecode(
      await (await reporter.list()).single.readAsString(),
    );
    expect(body['context'], {
      'object': '[UNSERIALIZABLE]',
      'number': '[UNSERIALIZABLE]',
    });
  });

  test('a disk failure does not poison the queue', () async {
    final blocker = File('${dir.path}/blocked');
    await blocker.writeAsString('block directory creation');
    final broken = FileCrashReporter(Directory(blocker.path));
    await expectLater(
      broken.recordError(
        StateError('first'),
        StackTrace.current,
        reason: 'test',
      ),
      throwsA(isA<FileSystemException>()),
    );
    await blocker.delete();
    await broken.recordError(
      StateError('second'),
      StackTrace.current,
      reason: 'test',
    );
    expect(await broken.count(), 1);
  });

  test(
    'abandoned owned temporary writes are cleaned without touching other files',
    () async {
      final pending = File('${dir.path}/crash-123.json.pending');
      final unrelated = File('${dir.path}/notes.pending');
      await pending.writeAsString('incomplete');
      await unrelated.writeAsString('unrelated');
      await reporter.clear();
      expect(await pending.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
    },
  );

  test(
    'default production reporter writes the real file store without export',
    () async {
      final c = ProviderContainer(
        overrides: [
          localCrashReportStoreProvider.overrideWith((ref) async => reporter),
        ],
      );
      addTearDown(c.dispose);
      await c
          .read(crashReporterProvider)
          .recordError(
            StateError('real'),
            StackTrace.current,
            reason: 'production_path',
          );
      expect(await reporter.count(), 1);
    },
  );

  test(
    'unavailable storage still reports to console and web creates no store',
    () async {
      final log = MemoryLogSink();
      final c = ProviderContainer(
        overrides: [
          logSinksProvider.overrideWithValue([log]),
          localCrashReportStoreProvider.overrideWith(
            (ref) async => throw StateError('storage-secret-sentinel'),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c
          .read(crashReporterProvider)
          .recordError(
            StateError('controlled'),
            StackTrace.current,
            reason: 'fallback',
          );
      expect(log.entries, hasLength(1));
      expect(await web.createLocalCrashReportStore(), isNull);
    },
  );
}
