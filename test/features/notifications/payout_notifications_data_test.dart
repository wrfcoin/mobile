import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/notifications/data/ntfy_poller.dart';
import 'package:wrfcoin_mobile/features/notifications/data/payout_notifications.dart';

const _address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _id = '6f1d2c4e-8a8b-4c1e-9d6a-1f2e3d4c5b6a';
const _topic = 'wrfcoin-pay-0011223344556677';

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
  'error': {'code': code, 'message': 'words'},
}, status);

(ApiPayoutNotificationRepository, _Server) _repository(
  ResponseBody Function(RequestOptions options) answer, {
  bool signedIn = true,
}) {
  final server = _Server(answer);
  final dio = Dio(BaseOptions(baseUrl: 'https://test.example/api'))
    ..httpClientAdapter = server;
  return (
    ApiPayoutNotificationRepository(
      dio,
      signIn: () async => signedIn,
      hasSession: () async => signedIn,
    ),
    server,
  );
}

void main() {
  group('config', () {
    test('reads what https://wrfcoin.com answers', () async {
      final (repository, server) = _repository(
        (_) => _json({
          'enabled': true,
          'events': ['payout.credited'],
          'checkEveryMinutes': 5,
          'webPush': {'available': true, 'publicKey': 'BDL3'},
          'ntfy': {'available': true, 'server': 'https://ntfy.sh'},
          'stores': 'An address and a topic.',
        }, 200),
      );
      final config = (await repository.config()).getOrElse(
        (failure) => fail(failure.message),
      );
      expect(server.requests.single.path, '/notifications/config');
      expect(config.enabled, isTrue);
      expect(config.checkEveryMinutes, 5);
      expect(config.ntfyServer, 'https://ntfy.sh');
    });

    test('no ntfy, or a server that is not https, means no server', () {
      for (final ntfy in [
        {'available': false, 'server': null},
        {'available': true, 'server': 'http://ntfy.sh'},
        null,
      ]) {
        expect(
          NotificationConfig.fromJson({'enabled': true, 'ntfy': ntfy})
              .ntfyServer,
          isNull,
        );
      }
    });

    test('a body off contract is an error, not "off"', () async {
      final (repository, _) = _repository((_) => _json({'ok': 1}, 200));
      expect(
        (await repository.config()).getLeft().toNullable(),
        isA<ServerFailure>(),
      );
    });

    test('the edge 404 means the feature is not here', () async {
      final (repository, _) = _repository(
        (_) => ResponseBody.fromString('Not found', 404),
      );
      expect(
        (await repository.config()).getLeft().toNullable(),
        isA<NotAvailableFailure>(),
      );
    });
  });

  group('subscriptions', () {
    test(
      'subscribe sends the address, channel and topic, nothing else',
      () async {
        final (repository, server) = _repository(
          (_) => _json({
            'success': true,
            'subscription': {
              'id': _id,
              'channel': 'ntfy',
              'label': _topic,
              'lastDeliveredAt': null,
            },
          }, 201),
        );
        final result = await repository.subscribeTopic(_address, _topic);
        expect(result.isRight(), isTrue);
        final request = server.requests.single;
        expect(request.method, 'POST');
        expect(request.path, '/notifications/subscriptions');
        expect(request.data, {
          'address': _address,
          'channel': 'ntfy',
          'topic': _topic,
        });
        expect(request.extra['noRetry'], isTrue);
      },
    );

    test('list parses the server view', () async {
      final (repository, server) = _repository(
        (_) => _json({
          'success': true,
          'address': _address,
          'subscriptions': [
            {
              'id': _id,
              'channel': 'ntfy',
              'label': _topic,
              'lastDeliveredAt': '2026-11-02T00:00:00.000Z',
            },
            {'id': _id, 'channel': 'webpush', 'label': 'fcm.example'},
          ],
          'lastCheck': null,
        }, 200),
      );
      final items = (await repository.list(_address))
          .getOrElse((failure) => fail(failure.message));
      expect(
        server.requests.single.path,
        '/notifications/subscriptions/$_address',
      );
      expect(items.first.label, _topic);
      expect(items.first.lastDeliveredAt, isNotNull);
      expect(items.last.channel, 'webpush');
    });

    test('test and remove use the subscription routes', () async {
      final (repository, server) = _repository(
        (o) => o.method == 'DELETE'
            ? _json({'success': true, 'removed': 1}, 200)
            : _json({'success': true, 'delivered': true}, 200),
      );
      expect((await repository.sendTest(_id)).getOrElse((_) => false), isTrue);
      expect(
        server.requests.last.path,
        '/notifications/subscriptions/$_id/test',
      );
      expect(server.requests.last.data, isA<Map<String, dynamic>>());
      expect((await repository.remove(_id)).isRight(), isTrue);
      expect(server.requests.last.method, 'DELETE');
      expect(server.requests.last.path, '/notifications/subscriptions/$_id');
    });

    test('stopping a topic needs no sign-in', () async {
      final (repository, server) = _repository(
        (_) => _json({'success': true, 'removed': 1}, 200),
        signedIn: false,
      );
      expect((await repository.stopTopic(_topic)).isRight(), isTrue);
      expect(server.requests.single.path, '/notifications/unsubscribe');
      expect(server.requests.single.data, {'channel': 'ntfy', 'topic': _topic});
    });

    test('nothing that needs the wallet leaves without a sign-in', () async {
      final (repository, server) = _repository(
        (_) => _json({'success': true}, 200),
        signedIn: false,
      );
      final results = [
        await repository.subscribeTopic(_address, _topic),
        await repository.remove(_id),
        await repository.sendTest(_id),
      ];
      expect(server.requests, isEmpty);
      for (final result in results) {
        expect(result.isLeft(), isTrue);
      }
    });

    test('refusals say what happened', () async {
      const cases = {
        'TOO_MANY_SUBSCRIPTIONS':
            'This address already has the maximum of 10 devices or topics.',
        'TEST_COOLDOWN': 'One test per minute. Try again shortly.',
      };
      for (final entry in cases.entries) {
        final (repository, _) = _repository(
          (_) => _refused(entry.key == 'TEST_COOLDOWN' ? 429 : 409, entry.key),
        );
        expect(
          (await repository.sendTest(_id)).getLeft().toNullable()?.message,
          entry.value,
        );
      }
      final (expired, _) = _repository(
        (_) => _refused(401, 'WALLET_LOGIN_REQUIRED'),
      );
      expect(
        (await expired.list(_address)).getLeft().toNullable(),
        isA<AuthFailure>(),
      );
      final (other, _) = _repository((_) => _refused(403, 'WALLET_MISMATCH'));
      expect(
        (await other.list(_address)).getLeft().toNullable()?.message,
        'The signed-in wallet is not this address.',
      );
      final (off, _) = _repository(
        (_) => _refused(503, 'NOTIFICATIONS_DISABLED'),
      );
      expect(
        (await off.list(_address)).getLeft().toNullable(),
        isA<NotAvailableFailure>(),
      );
      final (down, _) = _repository((_) => _refused(503, 'UNAVAILABLE'));
      expect(
        (await down.list(_address)).getLeft().toNullable(),
        isA<ServerFailure>(),
      );
    });
  });

  group('topic', () {
    test('a new topic passes the server rule and is not a constant', () {
      final one = suggestNtfyTopic();
      expect(ntfyTopicPattern.hasMatch(one), isTrue);
      expect(one, startsWith('wrfcoin-pay-'));
      expect(one, hasLength('wrfcoin-pay-'.length + 16));
      expect(suggestNtfyTopic(), isNot(one));
      expect(suggestNtfyTopic(Random(1)), suggestNtfyTopic(Random(1)));
    });
  });

  group('reading ntfy', () {
    const store = NtfyDeviceStore();
    late List<String> shown;

    Future<void> show({
      required int id,
      required String title,
      required String body,
    }) async => shown.add('$title|$body');

    NtfyPoller poller(_Server server) => NtfyPoller(
      store: store,
      show: show,
      dio: Dio()..httpClientAdapter = server,
    );

    setUp(() {
      shown = [];
      SharedPreferences.setMockInitialValues({});
    });

    String line(String id, {String event = 'message', String? title}) =>
        jsonEncode({
          'id': id,
          'time': 1800000000,
          'event': event,
          'topic': _topic,
          'title': ?title,
          'message': 'paid $id',
        });

    test('only message events count, bad lines are skipped', () {
      final messages = parseNtfyMessages(
        [
          line('o1', event: 'open'),
          line('k1', event: 'keepalive'),
          'not json',
          '',
          line('m1', title: 'WRFCoin payout'),
          line('m2'),
          '{"event":"message"}',
        ].join('\n'),
      );
      expect(messages.map((m) => m.id), ['m1', 'm2']);
      expect(messages.first.title, 'WRFCoin payout');
      expect(messages.last.title, 'WRFCoin');
    });

    test('off: nothing is asked of ntfy', () async {
      final server = _Server((_) => ResponseBody.fromString('', 200));
      expect(await poller(server).pollOnce(), 0);
      expect(server.requests, isEmpty);
    });

    test('reads from where it left off, shows, and moves on', () async {
      await store.save(topic: _topic, server: 'https://ntfy.sh', since: '1700');
      final server = _Server(
        (_) => ResponseBody.fromString('${line('m1')}\n${line('m2')}\n', 200),
      );
      final dio = poller(server);
      expect(await dio.pollOnce(), 2);
      final request = server.requests.single;
      expect(
        request.uri.toString(),
        startsWith('https://ntfy.sh/$_topic/json'),
      );
      expect(request.uri.queryParameters, {'poll': '1', 'since': '1700'});
      expect(shown, ['WRFCoin|paid m1', 'WRFCoin|paid m2']);
      expect(await store.since(), 'm2');
    });

    test('the wallet session never goes to ntfy', () async {
      await store.save(topic: _topic, server: 'https://ntfy.sh', since: '1');
      final server = _Server((_) => ResponseBody.fromString('', 200));
      await poller(server).pollOnce();
      expect(
        server.requests.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    });

    test('a burst shows only the newest, and still moves past all', () async {
      await store.save(topic: _topic, server: 'https://ntfy.sh', since: '1');
      final server = _Server(
        (_) => ResponseBody.fromString(
          List.generate(8, (i) => line('m$i')).join('\n'),
          200,
        ),
      );
      expect(await poller(server).pollOnce(), NtfyPoller.maxShownPerPoll);
      expect(shown.first, 'WRFCoin|paid m3');
      expect(await store.since(), 'm7');
    });

    test('offline keeps the place, so nothing is lost', () async {
      await store.save(topic: _topic, server: 'https://ntfy.sh', since: 'm1');
      final server = _Server(
        (_) => throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(await poller(server).pollOnce(), 0);
      expect(await store.since(), 'm1');
    });

    test('a stored plain-http server or bad topic is refused', () async {
      await store.save(topic: _topic, server: 'http://ntfy.sh', since: '1');
      final server = _Server((_) => ResponseBody.fromString('', 200));
      expect(await poller(server).pollOnce(), 0);
      await store.save(
        topic: 'bad/topic',
        server: 'https://ntfy.sh',
        since: '1',
      );
      expect(await poller(server).pollOnce(), 0);
      expect(server.requests, isEmpty);
    });

    test('clearing forgets the topic and the place', () async {
      await store.save(topic: _topic, server: 'https://ntfy.sh', since: '1');
      await store.clear();
      expect(await store.topic(), isNull);
      expect(await store.since(), isNull);
    });
  });
}
