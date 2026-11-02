import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/duels/data/models/duel_model.dart';
import 'package:wrfcoin_mobile/features/duels/data/repositories/duel_repository.dart';

import 'duel_fixtures.dart';

class _Server implements HttpClientAdapter {
  _Server(this.answer);
  final ResponseBody Function(RequestOptions options) answer;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return answer(options);
  }
}

ResponseBody _json(Object data, int status) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _refused(int status, String code) => _json({
  'success': false,
  'error': {'code': code, 'message': 'server words for $code'},
}, status);

(ApiDuelRepository, _Server) _repository(
  ResponseBody Function(RequestOptions options) answer, {
  bool signedIn = true,
}) {
  final server = _Server(answer);
  final dio = Dio(BaseOptions(baseUrl: 'https://test.example/api'))
    ..httpClientAdapter = server;
  return (ApiDuelRepository(dio, signIn: () async => signedIn), server);
}

void main() {
  test('reads the board from GET /duels with no query', () async {
    final (repository, server) = _repository(
      (_) => _json({
        'open': [openDuelJson()],
        'live': [liveDuelJson()],
        'finished': [finishedDuelJson()],
      }, 200),
    );
    final board = (await repository.getBoard()).getOrElse(
      (failure) => fail('unexpected ${failure.message}'),
    );
    expect(server.requests.single.method, 'GET');
    expect(server.requests.single.path, '/duels');
    expect(server.requests.single.queryParameters, isEmpty);
    expect(board.open.single.phase, 'open');
    expect(board.open.single.creator?.address, duelWalletA);
    expect(board.open.single.opponent, isNull);
    expect(board.live.single.opponent?.commitId, isNotNull);
    expect(board.live.single.creator?.temperatureC, isNull);
    final done = board.finished.single;
    expect(done.outcome?.winner, duelWalletA);
    expect(done.creator?.temperatureC, 12.5);
    expect(done.creator?.chainReward, '25000000');
  });

  test('a board with no lists is an error, not an empty board', () async {
    final (repository, _) = _repository((_) => _json({'ok': true}, 200));
    final failure = (await repository.getBoard()).getLeft().toNullable();
    expect(failure, isA<ServerFailure>());
  });

  test('the edge 404 (text, no code) means duels are off', () async {
    final (repository, _) = _repository(
      (_) => ResponseBody.fromString('Not found', 404),
    );
    expect(
      (await repository.getBoard()).getLeft().toNullable(),
      isA<NotAvailableFailure>(),
    );
  });

  test('offline, overloaded and down each say so', () async {
    final (limited, _) = _repository((_) => _refused(429, 'RATE_LIMITED'));
    expect(
      (await limited.getBoard()).getLeft().toNullable()?.message,
      contains('Too many requests'),
    );
    final (down, _) = _repository((_) => _refused(503, 'UNAVAILABLE'));
    expect(
      (await down.getBoard()).getLeft().toNullable(),
      isA<ServerFailure>(),
    );
  });

  test('open posts the server contract, never replayed', () async {
    final (repository, server) = _repository(
      (_) => _json({'duel': openDuelJson()}, 201),
    );
    final result = await repository.open(
      OpenDuelInput(
        stationAlias: 'st_7d29a4c1e0b8',
        targetAt: DateTime.utc(2026, 11, 2, 11),
      ),
    );
    expect(result.isRight(), isTrue);
    final request = server.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/duels');
    expect(request.data, {
      'stationAlias': 'st_7d29a4c1e0b8',
      'targetAt': '2026-11-02T11:00:00.000Z',
    });
    expect(request.extra['noRetry'], isTrue);
  });

  test('accept posts a JSON body, because the edge requires one', () async {
    final (repository, server) = _repository(
      (_) => _json({'duel': liveDuelJson()}, 200),
    );
    await repository.accept(duelIdForTest);
    final request = server.requests.single;
    expect(request.path, '/duels/$duelIdForTest/accept');
    expect(request.data, isA<Map<String, dynamic>>());
    expect(request.extra['noRetry'], isTrue);
  });

  test('link posts the commit id', () async {
    final (repository, server) = _repository(
      (_) => _json({'duel': liveDuelJson()}, 200),
    );
    await repository.linkForecast(duelIdForTest, 'ab' * 32);
    expect(server.requests.single.path, '/duels/$duelIdForTest/forecast');
    expect(server.requests.single.data, {'commitId': 'ab' * 32});
  });

  test('no wallet write leaves the phone without a sign-in', () async {
    final (repository, server) = _repository(
      (_) => _json({'duel': openDuelJson()}, 200),
      signedIn: false,
    );
    final results = [
      await repository.accept(duelIdForTest),
      await repository.linkForecast(duelIdForTest, 'ab' * 32),
      await repository.open(
        OpenDuelInput(
          stationAlias: 'st_7d29a4c1e0b8',
          targetAt: DateTime.utc(2026, 11, 2, 11),
        ),
      ),
    ];
    expect(server.requests, isEmpty);
    for (final result in results) {
      expect(result.getLeft().toNullable(), isA<AuthFailure>());
    }
  });

  test('a record hand-in needs no sign-in: it proves itself', () async {
    final (repository, server) = _repository(
      (_) => _json({'duel': liveDuelJson()}, 200),
      signedIn: false,
    );
    final result = await repository.handInRecord(
      duelIdForTest,
      DuelRecordInput.parse(
        '{"commit_id":"AB","nonce":"n","timestamp":"t"}',
        '{"x":1}',
      ),
    );
    expect(result.isRight(), isTrue);
    expect(server.requests.single.path, '/duels/$duelIdForTest/record');
    expect(server.requests.single.data, {
      'commitId': 'ab',
      'nonce': 'n',
      'timestamp': 't',
      'data': '{"x":1}',
    });
  });

  test('refusals use the same words as the web page', () async {
    const cases = {
      'OWN_DUEL': 'You opened this duel; another wallet must accept it.',
      'COMMIT_MISMATCH': 'These files do not hash to that commit id.',
      'UNKNOWN_STATION':
          "No station has that alias. Copy it from the station's page.",
    };
    for (final entry in cases.entries) {
      final (repository, _) = _repository((_) => _refused(409, entry.key));
      expect(
        (await repository.accept(duelIdForTest))
            .getLeft()
            .toNullable()
            ?.message,
        entry.value,
      );
    }
    final (other, _) = _repository((_) => _refused(400, 'SOMETHING_NEW'));
    expect(
      (await other.accept(duelIdForTest)).getLeft().toNullable()?.message,
      'server words for SOMETHING_NEW',
    );
  });

  test('a lapsed session is a sign-in failure', () async {
    final (repository, _) = _repository((_) => _refused(401, 'TOKEN_EXPIRED'));
    expect(
      (await repository.accept(duelIdForTest)).getLeft().toNullable(),
      isA<AuthFailure>(),
    );
  });

  test('a duel id the server does not know is "no such duel"', () async {
    final (repository, _) = _repository((_) => _refused(404, 'NO_SUCH_DUEL'));
    expect(
      (await repository.getDuel(duelIdForTest)).getLeft().toNullable(),
      isA<NotAvailableFailure>(),
    );
  });
}
