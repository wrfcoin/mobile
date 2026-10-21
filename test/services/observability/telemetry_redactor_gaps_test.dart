import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/observability/file_crash_reporter.dart';
import 'package:wrfcoin_mobile/services/observability/telemetry_redactor.dart';

String _r(String text) =>
    TelemetryRedactor.redactMap(<String, dynamic>{'message': text})['message']
        as String;

const _words12 =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

final words = _words12.split(' ');

void main() {
  group('long hex runs (signatures, keys)', () {
    test('a 128-hex signature is redacted', () {
      final sig = 'ab' * 64;
      expect(_r('bad signature $sig here'), 'bad signature [REDACTED] here');
    });

    test(
      'any run of 64 or more hex digits is redacted, with or without 0x',
      () {
        for (final n in [64, 65, 96, 128, 200]) {
          final run = 'c' * n;
          expect(
            _r('k=$run'),
            isNot(contains('cccccccc')),
            reason: '$n digits',
          );
          expect(_r('k=0x$run'), isNot(contains('cccccccc')), reason: '0x $n');
        }
      },
    );

    test('ordinary shorter hex and words are left alone', () {
      expect(_r('commit deadbeef1234 built'), 'commit deadbeef1234 built');
      expect(_r('id ${'a' * 63} end'), contains('a' * 63));
    });
  });

  group('mnemonic word lists in any separator', () {
    test('spaces, commas, semicolons, newlines and mixed', () {
      for (final sep in [' ', ', ', ',', '; ', '\n', ' ,\n']) {
        final text = 'restore failed: ${words.join(sep)} (end)';
        expect(
          _r(text),
          'restore failed: [REDACTED] (end)',
          reason: 'sep "$sep"',
        );
      }
    });

    test('24 words and a list embedded mid-sentence are redacted', () {
      expect(
        _r('x ${List.filled(24, 'abandon').join(', ')} y'),
        'x [REDACTED] y',
      );
    });

    test('fewer than 12 words are left alone', () {
      final eleven = _words12.split(' ').take(11).join(', ');
      expect(_r('list: $eleven'), 'list: $eleven');
    });
  });

  group('secret-like query parameters', () {
    test('opaque values of token/key/secret/auth/sig params are redacted', () {
      expect(
        _r('GET https://h/x?token=AbCdEfGhIjKlMnOp1234&page=2 failed'),
        'GET https://h/x?token=[REDACTED]&page=2 failed',
      );
      for (final p in [
        'api_key',
        'apikey',
        'secret',
        'auth',
        'access_token',
        'sig',
        'signature',
        'client-secret',
      ]) {
        expect(
          _r('https://h/x?a=1&$p=Zm9vYmFy&b=2'),
          'https://h/x?a=1&$p=[REDACTED]&b=2',
          reason: p,
        );
      }
    });

    test('non-secret params are untouched', () {
      expect(_r('https://h/x?page=2&sort=asc'), 'https://h/x?page=2&sort=asc');
      expect(
        _r('https://h/x?monkey=1&keyboard=2'),
        'https://h/x?monkey=1&keyboard=2',
      );
    });
  });

  group('coordinates finer than 0.1 degree', () {
    test(
      'lat/lon pairs and labelled values at 2 or more decimals are redacted',
      () {
        expect(_r('fix at 10.12, 20.45 failed'), 'fix at [REDACTED] failed');
        expect(_r('fix at -10.123 20.456 failed'), 'fix at [REDACTED] failed');
        expect(_r('lat=10.12 lon=-20.45'), 'lat=[REDACTED] lon=[REDACTED]');
        expect(
          _r('latitude: 10.12, longitude: 20.45'),
          'latitude: [REDACTED], longitude: [REDACTED]',
        );
        expect(
          _r('lat=10.123456 lon=-20.654321'),
          'lat=[REDACTED] lon=[REDACTED]',
        );
      },
    );

    test('0.1 degree values and ordinary decimals are untouched', () {
      expect(_r('cell 10.1, 20.4'), 'cell 10.1, 20.4');
      expect(_r('lat=10.1 lon=20.4'), 'lat=10.1 lon=20.4');
      expect(
        _r('took 12.34 ms, price 1.25, version 1.20'),
        'took 12.34 ms, price 1.25, version 1.20',
      );
    });
  });

  test('existing behaviours still hold', () {
    expect(_r(_words12), '[REDACTED]');
    expect(_r('to 0x${'12' * 20} failed'), 'to [REDACTED] failed');
    expect(
      _r(
        'jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop',
      ),
      'jwt [REDACTED]',
    );
  });

  group('iterables, serialized lists, encoded names, leading-dot decimals', () {
    test('a list of 12 or more word items is redacted as a whole', () {
      final r = TelemetryRedactor.redactMap(<String, dynamic>{
        'debug': <String, dynamic>{'words': words},
      });
      expect(r['debug']['words'], '[REDACTED]');
      final eleven = words.take(11).toList();
      expect(
        TelemetryRedactor.redactMap(<String, dynamic>{'w': eleven})['w'],
        eleven,
      );
    });

    test('quoted / JSON-encoded and bracketed lists in free text', () {
      expect(_r('bad: ${jsonEncode(words)}!'), 'bad: ["[REDACTED]"]!');
      expect(_r("x ['${words.join("', '")}']!"), "x ['[REDACTED]']!");
      final eleven = jsonEncode(words.take(11).toList());
      expect(_r('bad: $eleven'), 'bad: $eleven');
    });

    test('percent-encoded query names are classified after safe decoding', () {
      expect(
        _r('GET /x?tok%65n=OPAQUE_SENTINEL&page=2'),
        'GET /x?tok%65n=[REDACTED]&page=2',
      );
      expect(_r('/x?%61pi_key=AbC%2Bdef&a=1'), '/x?%61pi_key=[REDACTED]&a=1');
      // harmless and malformed encodings stay controlled
      expect(_r('/x?pa%67e=2&sort=asc'), '/x?pa%67e=2&sort=asc');
      expect(_r('/x?tok%zzen=abc&b=1'), '/x?tok%zzen=abc&b=1');
      expect(_r('/x?%=abc'), '/x?%=abc');
    });

    test('labelled leading-dot decimals are redacted, one decimal is kept', () {
      expect(_r('lat=.12 lon=-.34'), 'lat=[REDACTED] lon=[REDACTED]');
      expect(
        _r('latitude: +.123, longitude: -.456'),
        'latitude: [REDACTED], longitude: [REDACTED]',
      );
      expect(_r('lat=.1 lon=-.3'), 'lat=.1 lon=-.3');
      expect(_r('ratio .12 done'), 'ratio .12 done');
    });
  });

  group('apostrophes, JSON labels and escaped separators (round 2)', () {
    test('a secret query value is redacted whole, even with an apostrophe', () {
      expect(
        _r("GET /x?token=prefix'SUFFIX_SENTINEL&page=2"),
        'GET /x?token=[REDACTED]&page=2',
      );
      expect(_r("/x?api_key=a'b'c#frag"), '/x?api_key=[REDACTED]#frag');
      expect(_r("/x?q=it's&page=2"), "/x?q=it's&page=2");
    });

    test(
      'quoted JSON coordinate labels are redacted; coarse values are kept',
      () {
        expect(
          _r(jsonEncode({'lat': 0.12, 'lon': -0.34})),
          '{"lat":[REDACTED],"lon":[REDACTED]}',
        );
        expect(
          _r(jsonEncode({'latitude': 10.123, 'lng': -20.45})),
          '{"latitude":[REDACTED],"lng":[REDACTED]}',
        );
        expect(
          _r(jsonEncode({'lat': 0.1, 'lon': -0.3})),
          '{"lat":0.1,"lon":-0.3}',
        );
        expect(
          _r(jsonEncode({'price': 1.25, 'late': 0.12})),
          '{"price":1.25,"late":0.12}',
        );
      },
    );

    test(
      'JSON-escaped separators between words are redacted, 11 words kept',
      () {
        for (final sep in [r'\n', r'\r\n', r'\t', r'\u0020']) {
          final enc = words.join(sep);
          expect(_r('restore: "$enc"!'), 'restore: "[REDACTED]"!', reason: sep);
        }
        expect(
          _r('restore: ${jsonEncode(words.join('\n'))}!'),
          'restore: "[REDACTED]"!',
        );
        final eleven = jsonEncode(words.take(11).join('\n'));
        expect(_r('restore: $eleven!'), 'restore: $eleven!');
      },
    );
  });

  group('persisted and exported crash reports (disk)', () {
    late Directory dir;
    late FileCrashReporter reporter;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('redactor-gaps-');
      reporter = FileCrashReporter(dir, appVersion: 't', platform: 't');
    });
    tearDown(() async => dir.delete(recursive: true));

    Future<(String, String)> persist(
      Object error,
      Map<String, dynamic> ctx,
    ) async {
      await reporter.recordError(
        error,
        StackTrace.empty,
        reason: 'gap_test',
        context: ctx,
      );
      final onDisk = await reporter.list();
      final disk = await onDisk.single.readAsString();
      final exported = utf8.decode(
        await (await reporter.exportFiles()).single.readAsBytes(),
      );
      return (disk, exported);
    }

    test(
      'a word list in context never reaches the file or the export',
      () async {
        final (disk, exp) = await persist(StateError('e'), {
          'debug': {'words': words},
        });
        for (final t in [disk, exp]) {
          expect(t, isNot(contains('abandon')));
          expect(t, isNot(contains('accident')));
        }
      },
    );

    test('a JSON-encoded word list in an error never reaches the file or the export', () async {
      final (disk, exp) = await persist(
        StateError('restore ${jsonEncode(words)}'),
        {},
      );
      for (final t in [disk, exp]) {
        expect(t, isNot(contains('abandon')));
        expect(t, isNot(contains('accident')));
      }
    });

    test('a percent-encoded secret query value never reaches the file or the export', () async {
      final (disk, exp) = await persist(
        StateError(
          'GET https://example.invalid/x?tok%65n=OPAQUE_REVIEW_SENTINEL&page=2',
        ),
        {},
      );
      for (final t in [disk, exp]) {
        expect(t, isNot(contains('OPAQUE_REVIEW_SENTINEL')));
        expect(t, contains('page=2'));
      }
    });

    test(
      'labelled leading-dot coordinates never reach the file or the export',
      () async {
        final (disk, exp) = await persist(
          StateError('at lat=.12 lon=-.34 failed'),
          {},
        );
        for (final t in [disk, exp]) {
          expect(t, isNot(contains('.12')));
          expect(t, isNot(contains('.34')));
        }
      },
    );

    test(
      'an apostrophe secret query value never reaches the file or the export',
      () async {
        final (disk, exp) = await persist(
          StateError(
            "GET https://example.invalid/x?token=prefix'QUERY_SUFFIX_SENTINEL&page=2",
          ),
          {},
        );
        for (final t in [disk, exp]) {
          expect(t, isNot(contains('QUERY_SUFFIX_SENTINEL')));
          expect(t, isNot(contains('prefix')));
          expect(t, contains('page=2'));
        }
      },
    );

    test(
      'JSON labelled coordinates never reach the file or the export',
      () async {
        final (disk, exp) = await persist(
          StateError('at ${jsonEncode({'lat': .12, 'lon': -.34})}'),
          {},
        );
        for (final t in [disk, exp]) {
          expect(t, isNot(contains('0.12')));
          expect(t, isNot(contains('0.34')));
        }
      },
    );

    test(
      'a JSON-escaped-newline word list never reaches the file or the export',
      () async {
        final (disk, exp) = await persist(
          StateError('restore ${jsonEncode(words.join('\n'))}'),
          {},
        );
        for (final t in [disk, exp]) {
          expect(t, isNot(contains('abandon')));
          expect(t, isNot(contains('accident')));
        }
      },
    );
  });
}
