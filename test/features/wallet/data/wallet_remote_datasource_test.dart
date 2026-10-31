import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';

void main() {
  test('schema-v2 preserves tx_type when kind and type are absent', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'schemaVersion': 2,
                'items': [
                  {
                    'txId': 'commit',
                    'tx_type': 'ContributionCommit',
                    'kind': null,
                    'direction': 'unknown',
                    'amountBaseUnits': null,
                    'settlement': 'included',
                  },
                  {'txId': 'unknown', 'direction': 'unknown'},
                ],
              },
            ),
          );
        },
      ),
    );
    final page = await WalletRemoteDataSource(dio).getTransactions('synthetic');
    expect(page.items.first.type, 'ContributionCommit');
    expect(page.items.first.direction, 'unknown');
    expect(page.items.first.value, isNull);
    expect(page.items.last.type, 'unknown');
  });

  test(
    'reward rows are gated and deduped across items and creditItems',
    () async {
      const own = '0x1111111111111111111111111111111111111111';
      Map<String, dynamic> reward(String id, {String settlement = 'paid'}) => {
        'eventId': id,
        'txId': null,
        'from': null,
        'to': own,
        'amountBaseUnits': '100',
        'direction': 'received',
        'kind': 'weather_reward',
        'type': 'weather_reward',
        'settlement': settlement,
      };
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'schemaVersion': 2,
                'items': [
                  reward('contribution:a'),
                  reward('contribution:a'),
                  reward('contribution:unpaid', settlement: 'pending'),
                ],
                'creditItems': [
                  reward('contribution:a'),
                  reward('contribution:b'),
                ],
              },
            ),
          ),
        ),
      );
      final page = await WalletRemoteDataSource(dio).getTransactions(own);
      expect(page.items.map((t) => t.eventId), ['contribution:a']);
      expect(page.credits.map((t) => t.eventId), ['contribution:b']);
    },
  );

  group('WalletRemoteDataSource', () {
    late Dio dio;
    late WalletRemoteDataSource dataSource;

    setUp(() {
      dio = Dio();
      dataSource = WalletRemoteDataSource(dio);
    });

    const hex = 'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';
    const chainAddress = '0x$hex';

    void answer(Object? data, {int status = 200, List<String>? paths}) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            paths?.add(options.path);
            final response = Response<dynamic>(
              requestOptions: options,
              statusCode: status,
              data: data,
            );
            if (status >= 400) {
              handler.reject(
                DioException.badResponse(
                  statusCode: status,
                  requestOptions: options,
                  response: response,
                ),
              );
            } else {
              handler.resolve(response);
            }
          },
        ),
      );
    }

    for (final held in [
      chainAddress,
      '0X${hex.toUpperCase()}',
      'wrf$hex',
      'WRF${hex.toUpperCase()}',
    ]) {
      test('reads the public balance route for $held', () async {
        final paths = <String>[];
        answer({
          'address': chainAddress,
          'balance': '150000000',
          'height': 10262,
          'earned': '250000000',
        }, paths: paths);
        final wallet = await dataSource.getWallet(held);
        expect(paths, ['/public/balance/$chainAddress']);
        expect(wallet.address, held, reason: 'the held address is kept');
        expect(wallet.balance, '150000000');
        expect(wallet.earnedBalanceTotal, '250000000');
        expect(wallet.height, 10262);
        expect(wallet.balanceAvailability, BalanceAvailability.reported);
        expect(wallet.balanceText, '1.5 WRF');
      });
    }

    test('reported zeros are real, a null earned stays unavailable', () async {
      answer({
        'address': chainAddress,
        'balance': '0',
        'height': 1,
        'earned': null,
      });
      final wallet = await dataSource.getWallet(chainAddress);
      expect(wallet.balance, '0');
      expect(wallet.balanceText, '0 WRF');
      expect(wallet.earnedBalanceTotal, isNull);
    });

    test('large base-unit strings survive without floating point', () async {
      answer({
        'address': chainAddress,
        'balance': '9007199254740993123456789',
        'height': 5,
        'earned': '9007199254740993123456789',
      });
      final wallet = await dataSource.getWallet(chainAddress);
      final json = WalletModel.fromJson(wallet.toJson()).toJson();
      expect(json['balance'], '9007199254740993123456789');
      expect(json['earnedBalanceTotal'], '9007199254740993123456789');
    });

    test('404 (public reads off) is Unavailable, never zero', () async {
      answer({'error': 'Not found'}, status: 404);
      final wallet = await dataSource.getWallet(chainAddress);
      expect(wallet.balance, isNull);
      expect(wallet.earnedBalanceTotal, isNull);
      expect(wallet.balanceAvailability, BalanceAvailability.unavailable);
      expect(wallet.balanceText, 'Unavailable');
    });

    test('429 (rate limited) is Busy', () async {
      answer({'error': 'Too many requests'}, status: 429);
      final wallet = await dataSource.getWallet(chainAddress);
      expect(wallet.balance, isNull);
      expect(wallet.balanceAvailability, BalanceAvailability.busy);
      expect(wallet.balanceText, 'Busy');
    });

    test('other failures are thrown for the repository to map', () async {
      answer({'error': 'boom'}, status: 503);
      await expectLater(
        dataSource.getWallet(chainAddress),
        throwsA(isA<DioException>()),
      );
    });

    for (final entry in {
      'another address': {
        'address': '0x${'1' * 40}',
        'balance': '5',
        'height': 1,
        'earned': '5',
      },
      'a display amount': {
        'address': chainAddress,
        'balance': '1.5 WRF',
        'height': 1,
        'earned': '0',
      },
      'a negative balance': {
        'address': chainAddress,
        'balance': '-1',
        'height': 1,
        'earned': '0',
      },
      'no balance': {'address': chainAddress, 'height': 1, 'earned': '0'},
      'an HTML page': '<html>Not found</html>',
    }.entries) {
      test('an answer with ${entry.key} is Unavailable', () async {
        answer(entry.value);
        final wallet = await dataSource.getWallet(chainAddress);
        expect(wallet.balance, isNull);
        expect(wallet.balanceAvailability, BalanceAvailability.unavailable);
      });
    }

    test('a malformed earned total is unavailable, not zero', () async {
      answer({
        'address': chainAddress,
        'balance': '7',
        'height': 1,
        'earned': '1.0',
      });
      final wallet = await dataSource.getWallet(chainAddress);
      expect(wallet.balance, '7');
      expect(wallet.earnedBalanceTotal, isNull);
    });

    test(
      'an address that is not 20 bytes is refused before any request',
      () async {
        final paths = <String>[];
        answer(const {}, paths: paths);
        await expectLater(
          dataSource.getWallet('wrf1wallet'),
          throwsArgumentError,
        );
        expect(paths, isEmpty);
      },
    );

    test('model JSON and copyWith preserve unavailable values', () {
      final missing = WalletModel.fromJson({'address': chainAddress});
      expect(missing.balance, isNull);
      expect(missing.balanceAvailability, BalanceAvailability.reported);
      expect(missing.balanceText, 'Unavailable');
      final busy = missing.copyWith(
        balanceAvailability: BalanceAvailability.busy,
      );
      expect(WalletModel.fromJson(busy.toJson()), busy);
    });

    test('unwraps transaction lists from paginated API responses', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: const <String, dynamic>{
                  'success': true,
                  'data': {
                    'data': [
                      {
                        'hash': '0x1',
                        'from': 'wrf1wallet',
                        'to': 'wrf1dest',
                        'amount': '10.5',
                        'timestamp': '2026-03-10T00:00:00Z',
                        'fee': '0.001',
                        'token': 'WRF',
                      },
                    ],
                  },
                },
              ),
            );
          },
        ),
      );

      final page = await dataSource.getTransactions('wrf1wallet');
      final transactions = page.items;

      expect(transactions, hasLength(1));
      expect(transactions.single.value, '10.5');
      expect(transactions.single.fee, '0.001');
      expect(transactions.single.type, 'WRF');
      expect(transactions.single.direction, 'outgoing');
    });

    // The exact 200 body backend#1199 (1331b64a, server/routes/
    // wallet-routes.js GET /:address/transactions) sends: no direction,
    // status or timestamp, and `to`/`amount` explicitly null.
    const ownAddress = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const otherAddress = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    Map<String, dynamic> backendBody(List<Map<String, dynamic>> items) => {
      'items': items,
      'windowStartHeight': 1200,
      'source': 'core4',
      'complete': false,
      'limit': 20,
      'offset': 0,
      'totalInWindow': items.length,
    };

    void serve(Map<String, dynamic> body, [List<Uri>? requested]) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requested?.add(options.uri);
            handler.resolve(Response(requestOptions: options, data: body));
          },
        ),
      );
    }

    test(
      'keeps what the B3 body leaves out unset instead of inventing it',
      () async {
        serve(
          backendBody([
            {
              'txId': '0xb3',
              'blockHeight': 1234,
              'type': 'Transfer',
              'from': otherAddress,
              'to': null,
              'amount': null,
            },
          ]),
        );

        final page = await dataSource.getTransactions(ownAddress);
        final tx = page.items.single;

        expect(tx.hash, '0xb3');
        expect(tx.blockNumber, 1234);
        expect(tx.type, 'Transfer');
        expect(tx.value, isNull, reason: 'amount:null is not reported');
        expect(tx.to, isNull);
        expect(tx.status, isNull, reason: 'no status was sent');
        expect(tx.timestamp, isNull, reason: 'no timestamp was sent');
        expect(tx.direction, 'incoming', reason: 'sender is not this wallet');

        expect(page.complete, isFalse);
        expect(page.windowStartHeight, 1200);
        expect(page.totalInWindow, 1);
      },
    );

    test('derives sent from the own address, case-insensitively', () async {
      serve(
        backendBody([
          {
            'txId': '0xs',
            'blockHeight': 5,
            'type': 'Transfer',
            'from': ownAddress.toUpperCase().replaceFirst('0X', '0x'),
            'to': null,
            'amount': null,
          },
          {
            'txId': '0xu',
            'blockHeight': 6,
            'type': 'Transfer',
            'to': null,
            'amount': null,
          },
        ]),
      );

      final page = await dataSource.getTransactions(ownAddress);

      expect(page.items.first.direction, 'outgoing');
      expect(page.items.last.direction, 'unknown', reason: 'no sender');
    });

    test('pages by offset, which is all the backend reads', () async {
      final requested = <Uri>[];
      serve(backendBody(const []), requested);

      await dataSource.getTransactions(ownAddress, offset: 20, limit: 20);

      final query = requested.single.queryParameters;
      expect(query['offset'], '20');
      expect(query['limit'], '20');
      expect(query.containsKey('page'), isFalse);
    });
  });
}
