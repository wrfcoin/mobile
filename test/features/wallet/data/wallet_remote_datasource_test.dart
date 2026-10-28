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

  test('reward rows are gated and deduped across items and creditItems', () async {
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
  });

  group('WalletRemoteDataSource', () {
    late Dio dio;
    late WalletRemoteDataSource dataSource;

    setUp(() {
      dio = Dio();
      dataSource = WalletRemoteDataSource(dio);
    });

    for (final missing in [null, '', '   ', 'unavailable']) {
      test(
        'missing/invalid reward value $missing stays unavailable while balance zero is real',
        () async {
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    data: {
                      'success': true,
                      'data': {
                        'balance': '0',
                        'nonce': 0,
                        'transactions': 0,
                        'weatherRewards': ?missing,
                        'stakingRewards': ?missing,
                      },
                    },
                  ),
                );
              },
            ),
          );
          final wallet = await dataSource.getWallet('wrf1wallet');
          expect(wallet.balance, '0');
          expect(wallet.weatherRewards, isNull);
          expect(wallet.stakingRewards, isNull);
        },
      );
    }

    test('explicit zero rewards remain reported values', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'data': {
                    'balance': 0,
                    'weatherRewards': 0,
                    'stakingRewards': '0 WRF',
                  },
                },
              ),
            );
          },
        ),
      );
      final wallet = await dataSource.getWallet('wrf1wallet');
      expect(wallet.weatherRewards, '0');
      expect(wallet.stakingRewards, '0');
    });

    test('model JSON and copyWith preserve unavailable reward values', () {
      final missing = WalletModel.fromJson({
        'address': 'wrf1wallet',
        'balance': '0',
      });
      expect(missing.weatherRewards, isNull);
      expect(missing.stakingRewards, isNull);
      expect(WalletModel.fromJson(missing.toJson()).weatherRewards, isNull);
      final reported = missing.copyWith(
        weatherRewards: '2',
        stakingRewards: '0',
      );
      final cleared = (reported.copyWith as dynamic)(
        weatherRewards: null,
        stakingRewards: null,
      ) as WalletModel;
      expect(cleared.weatherRewards, isNull);
      expect(cleared.stakingRewards, isNull);
    });

    test(
      'unwraps wallet balance payloads and normalizes reward values',
      () async {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: const <String, dynamic>{
                    'success': true,
                    'data': {
                      'address': 'wrf1wallet',
                      'balance': '125.4589 WRF',
                      'stakingRewards': '12.45 WRF',
                      'weatherRewards': '8.92 WRF',
                      'transactionCount': 7,
                      'pendingTransactions': 2,
                    },
                  },
                ),
              );
            },
          ),
        );

        final wallet = await dataSource.getWallet('wrf1wallet');

        expect(wallet.address, 'wrf1wallet');
        expect(wallet.balance, '125.4589');
        expect(wallet.stakingRewards, '12.45');
        expect(wallet.weatherRewards, '8.92');
        expect(wallet.transactions, 7);
        expect(wallet.pendingTransactions, 2);
      },
    );

    test(
      'backend1364 chain totals survive datasource and model roundtrip',
      () async {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(options.path, '/wallet/wrf1wallet');
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'success': true,
                    'data': {
                      'balance': '99900000000',
                      'earned_balance_total': '9007199254740993123456789',
                      'earnedBalanceTotal': '9007199254740993123456789',
                      'weatherRewards': '125000000',
                      'weatherRewardsPending': '25000000',
                      'weatherRewardsUnavailable': null,
                    },
                  },
                ),
              );
            },
          ),
        );
        final wallet = await dataSource.getWallet('wrf1wallet');
        final json = WalletModel.fromJson(wallet.toJson()).toJson();
        expect(json['earnedBalanceTotal'], '9007199254740993123456789');
        expect(json['weatherRewards'], '125000000');
        expect(json['weatherRewardsPending'], '25000000');
        expect(json['weatherRewardsUnavailable'], isNull);
        expect(
          wallet.stakingRewards,
          isNull,
          reason: 'no fabricated bonus split',
        );
      },
    );

    test(
      'camel total alias and older-node unavailable reason are preserved',
      () async {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'data': {
                      'balance': '0',
                      'earnedBalanceTotal': '700000000',
                      'weatherRewards': null,
                      'weatherRewardsPending': null,
                      'weatherRewardsUnavailable':
                          'This node does not report contribution rewards.',
                    },
                  },
                ),
              );
            },
          ),
        );
        final json = (await dataSource.getWallet('wrf1wallet')).toJson();
        expect(json['earnedBalanceTotal'], '700000000');
        expect(json['weatherRewards'], isNull);
        expect(json['weatherRewardsPending'], isNull);
        expect(
          json['weatherRewardsUnavailable'],
          'This node does not report contribution rewards.',
        );
      },
    );

    test('new-wallet reported zeros remain real chain reward values', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'data': {
                    'exists': false,
                    'balance': '0',
                    'earned_balance_total': '0',
                    'weatherRewards': '0',
                    'weatherRewardsPending': '0',
                    'weatherRewardsUnavailable': null,
                  },
                },
              ),
            );
          },
        ),
      );
      final json = (await dataSource.getWallet('wrf1wallet')).toJson();
      expect(json['earnedBalanceTotal'], '0');
      expect(json['weatherRewardsPending'], '0');
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
