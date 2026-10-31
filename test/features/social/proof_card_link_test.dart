import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/social/proof_card_link.dart';

const _commit =
    'c0ffee000000000000000000000000000000000000000000000000004d2a91e7';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Object body;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _card({String status = 'included', int? height = 44809}) =>
    <String, dynamic>{
      'commitId': _commit,
      'inclusion': <String, dynamic>{
        'status': status,
        'block': status == 'included'
            ? <String, dynamic>{'height': height, 'hash': null}
            : null,
      },
    };

ProofCardLinkService _service(_Adapter adapter, List<String> shared) {
  final dio = Dio(BaseOptions(baseUrl: 'https://wrfcoin.com/api'))
    ..httpClientAdapter = adapter;
  return ProofCardLinkService(
    dio,
    shareLauncher: (text) async => shared.add(text),
  );
}

void main() {
  group('proofCardPageUri', () {
    test('builds the public page link, with the height only when real', () {
      expect(
        proofCardPageUri(_commit).toString(),
        'https://wrfcoin.com/proof/$_commit',
      );
      expect(
        proofCardPageUri(_commit, height: 44809).toString(),
        'https://wrfcoin.com/proof/$_commit?h=44809',
      );
      expect(
        proofCardPageUri(_commit, height: 0).toString(),
        'https://wrfcoin.com/proof/$_commit',
      );
      expect(
        proofCardPageUri(_commit, height: 1000000000000).toString(),
        'https://wrfcoin.com/proof/$_commit',
      );
    });

    test('refuses anything that is not a core4 commit id', () {
      expect(proofCardPageUri(null), isNull);
      expect(proofCardPageUri(_commit.toUpperCase()), isNull);
      expect(proofCardPageUri('0x$_commit'), isNull);
      expect(proofCardPageUri(_commit.substring(1)), isNull);
      expect(proofCardPageUri('submission-42'), isNull);
    });
  });

  group('ProofCardLinkService', () {
    test('adds the block height the public proof card read reports', () async {
      final adapter = _Adapter(200, _card());
      final shared = <String>[];
      final uri = await _service(adapter, shared).share(_commit);
      expect(uri.toString(), 'https://wrfcoin.com/proof/$_commit?h=44809');
      expect(adapter.paths.single, '/proofs/$_commit');
      expect(
        shared.single,
        contains('https://wrfcoin.com/proof/$_commit?h=44809'),
      );
    });

    test(
      'shares the bare link when the reading is not in a block yet',
      () async {
        final shared = <String>[];
        final uri = await _service(
          _Adapter(200, _card(status: 'not_located')),
          shared,
        ).share(_commit);
        expect(uri.toString(), 'https://wrfcoin.com/proof/$_commit');
      },
    );

    test('shares the bare link when the read is switched off or fails, never a guessed height', () async {
      for (final status in [404, 429, 502]) {
        final shared = <String>[];
        final uri = await _service(
          _Adapter(status, {'error': 'x'}),
          shared,
        ).share(_commit);
        expect(uri.toString(), 'https://wrfcoin.com/proof/$_commit');
        expect(shared, hasLength(1));
      }
    });

    test(
      'ignores an answer for a different commit or a non-integer height',
      () async {
        final other = Map<String, dynamic>.from(_card())
          ..['commitId'] = 'ab' * 32;
        expect(
          (await _service(_Adapter(200, other), []).resolve(_commit))
              .toString(),
          'https://wrfcoin.com/proof/$_commit',
        );
        final badHeight = _card()
          ..['inclusion'] = {
            'status': 'included',
            'block': {'height': '44809'},
          };
        expect(
          (await _service(_Adapter(200, badHeight), []).resolve(_commit))
              .toString(),
          'https://wrfcoin.com/proof/$_commit',
        );
      },
    );

    test('shares nothing and asks nothing for a malformed commit id', () async {
      final adapter = _Adapter(200, _card());
      final shared = <String>[];
      expect(await _service(adapter, shared).share('not-a-commit'), isNull);
      expect(adapter.paths, isEmpty);
      expect(shared, isEmpty);
    });
  });
}
