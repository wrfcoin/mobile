import 'dart:async';

// End-to-end wallet history: a real WalletRemoteDataSource and
// WalletRepositoryImpl behind the real transactions provider and
// WalletScreen, with Dio answering the backend#1199 contract
// (server/routes/wallet-routes.js GET /:address/transactions).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/wallet/data/datasources/wallet_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/wallet_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/transaction_history_unavailable_card.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/transaction_tile.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../../test_helpers/fakes.dart';

const _own = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _other = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

typedef _History = Response<dynamic> Function(RequestOptions options);

class _Backend {
  _Backend(this.history);

  final _History history;
  final List<Uri> historyRequests = <Uri>[];

  Dio dio() {
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('/transactions')) {
            historyRequests.add(options.uri);
            final response = history(options);
            final status = response.statusCode ?? 200;
            if (status >= 400) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: response,
                ),
              );
            } else {
              handler.resolve(response);
            }
            return;
          }
          if (options.path == '/wallet/$_own') {
            handler.resolve(
              Response(
                requestOptions: options,
                data: const {
                  'address': _own,
                  'balance': '42',
                  'transactions': 3,
                },
              ),
            );
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: options, statusCode: 404),
            ),
          );
        },
      ),
    );
    return dio;
  }
}

Map<String, dynamic> _item(
  String id, {
  required String from,
  int height = 1300,
}) => {
  'txId': id,
  'blockHeight': height,
  'type': 'Transfer',
  'from': from,
  'to': null,
  'amount': null,
};

Map<String, dynamic> _window(
  List<Map<String, dynamic>> items, {
  required int offset,
  required int total,
}) => {
  'items': items,
  'windowStartHeight': 1200,
  'source': 'core4',
  'complete': false,
  'limit': 20,
  'offset': offset,
  'totalInWindow': total,
};

class _FixedTransactions extends TransactionsNotifier {
  _FixedTransactions(this.fixture);
  final TransactionsState fixture;
  @override
  Future<TransactionsState> build() async => fixture;
}

Future<ProviderContainer> _pumpWallet(
  WidgetTester tester,
  _Backend backend, {
  TransactionsState? transactions,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final keyStorage = InMemoryKeyValueStorage();
  await keyStorage.write(key: 'wrf_address', value: _own);
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = backend.dio();

  final container = ProviderContainer(
    overrides: [
      if (transactions != null)
        transactionsProvider.overrideWith(
          () => _FixedTransactions(transactions),
        ),
      sharedPreferencesProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
      walletRepositoryProvider.overrideWithValue(
        WalletRepositoryImpl(WalletRemoteDataSource(dio)),
      ),
      keyManagerProvider.overrideWithValue(
        KeyManager(
          biometric: BiometricService(client: FakeLocalAuthClient()),
          storage: keyStorage,
        ),
      ),
      walletSecureStorageProvider.overrideWithValue(
        FakeWalletSecureStorage(backupConfirmed: true),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/wallet',
          routes: [
            GoRoute(path: '/wallet', builder: (_, _) => const WalletScreen()),
          ],
        ),
      ),
    ),
  );
  await _settle(tester);
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('Wallet shows the bounded-history notice', (tester) async {
    final backend = _Backend(
      (o) =>
          Response(requestOptions: o, data: _window([], offset: 0, total: 0)),
    );
    await _pumpWallet(
      tester,
      backend,
      transactions: const TransactionsState(
        items: [],
        hasMore: true,
        loadingMore: false,
        complete: false,
      ),
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Wallet')),
      findsOneWidget,
    );
    expect(find.text('Earnings'), findsNothing);
    expect(find.text('Showing recent activity only'), findsOneWidget);
    expect(backend.historyRequests, isEmpty);
  });

  testWidgets(
    'transaction row and details convert base-unit value and fee to WRF',
    (tester) async {
      final backend = _Backend(
        (o) => Response(
          requestOptions: o,
          statusCode: 200,
          data: _window(
            [
              {
                ..._item('0xunits', from: _other),
                'amount': '150000000',
                'fee': '150000',
              },
            ],
            offset: 0,
            total: 1,
          ),
        ),
      );
      await _pumpWallet(tester, backend);
      expect(find.text('+1.5 WRF'), findsOneWidget);
      await tester.tap(find.byType(TransactionTile));
      await _settle(tester);
      expect(find.text('Activity Details'), findsOneWidget);
      expect(find.text('1.5 WRF'), findsOneWidget);
      expect(find.text('0.0015 WRF'), findsOneWidget);
      expect(find.textContaining('credits'), findsNothing);
    },
  );

  testWidgets(
    '501 from the backend reaches the screen as the unavailable card',
    (tester) async {
      final backend = _Backend(
        (o) => Response(
          requestOptions: o,
          statusCode: 501,
          data: const {
            'error': {
              'message': 'Wallet transaction history is unavailable on this node version.',
              'details': 'capability: wallet.history',
            },
          },
        ),
      );
      final container = await _pumpWallet(tester, backend);

      expect(
        container.read(transactionsProvider).value?.historyUnavailable,
        isTrue,
      );
      expect(find.byType(TransactionHistoryUnavailableCard), findsOneWidget);
      expect(find.text('Something Went Wrong'), findsNothing);
      expect(find.byType(TransactionTile), findsNothing);
    },
  );

  testWidgets(
    '503 CORE4_READER_CREDENTIAL_UNCONFIGURED shows unavailable, not an error',
    (tester) async {
      final backend = _Backend(
        (o) => Response(
          requestOptions: o,
          statusCode: 503,
          data: const {
            'success': false,
            'error': {
              'code': 'CORE4_READER_CREDENTIAL_UNCONFIGURED',
              'message': 'Wallet chain reads are unavailable: the backend core4 Reader credential is not configured',
            },
            'timestamp': '2026-09-23T00:00:00.000Z',
          },
        ),
      );
      final container = await _pumpWallet(tester, backend);

      expect(
        container.read(transactionsProvider).value?.historyUnavailable,
        isTrue,
      );
      expect(find.byType(TransactionHistoryUnavailableCard), findsOneWidget);
      expect(find.text('Something Went Wrong'), findsNothing);
    },
  );

  testWidgets('second page requests offset=50 and appends without duplicates', (
    tester,
  ) async {
    final all = [
      for (var i = 0; i < 55; i++)
        _item('0xtx$i', from: _other, height: 1300 + i),
    ];
    final backend = _Backend((o) {
      // Like the real backend: only limit/offset are read, page is ignored.
      final offset = int.tryParse(o.uri.queryParameters['offset'] ?? '') ?? 0;
      final limit = int.tryParse(o.uri.queryParameters['limit'] ?? '') ?? 55;
      return Response(
        requestOptions: o,
        statusCode: 200,
        data: _window(
          all.skip(offset).take(limit).toList(),
          offset: offset,
          total: all.length,
        ),
      );
    });
    final container = await _pumpWallet(tester, backend);

    expect(find.byType(TransactionTile), findsNWidgets(50));
    expect(find.text('Load more'), findsOneWidget);

    await tester.ensureVisible(find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await _settle(tester);

    expect(backend.historyRequests, hasLength(2));
    expect(backend.historyRequests[0].queryParameters['offset'], '0');
    expect(backend.historyRequests[1].queryParameters['offset'], '50');

    final hashes = container
        .read(transactionsProvider)
        .value!
        .items
        .map((tx) => tx.hash)
        .toList();
    expect(hashes, hasLength(55));
    expect(hashes.toSet(), hasLength(55));
    expect(find.byType(TransactionTile), findsNWidgets(55));
    expect(find.text('Load more'), findsNothing, reason: '55 of 55 loaded');
  });

  testWidgets(
    'received vs sent comes from the sender, amounts are not invented',
    (tester) async {
      final backend = _Backend(
        (o) => Response(
          requestOptions: o,
          statusCode: 200,
          data: _window(
            [
              _item('0xin', from: _other),
              _item('0xout', from: _own.toUpperCase().replaceFirst('0X', '0x')),
            ],
            offset: 0,
            total: 2,
          ),
        ),
      );
      await _pumpWallet(tester, backend);

      expect(find.text('Received'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Amount not reported'), findsNWidgets(2));
      expect(find.textContaining('unavailable credits'), findsNothing);
      expect(
        find.text('confirmed'),
        findsNothing,
        reason: 'no status was sent',
      );
      expect(find.text('Showing activity since block 1200'), findsOneWidget);
    },
  );
  Map<String, dynamic> credit(String id, String kind, String amount) => {
    'eventId': id,
    'txId': null,
    'from': null,
    'to': _own,
    'amountBaseUnits': amount,
    'direction': 'received',
    'kind': kind,
    'type': kind,
    'settlement': 'paid',
    'timestamp': null,
  };

  testWidgets('paid earnings render exact amounts with stable event keys', (
    tester,
  ) async {
    final backend = _Backend(
      (o) => Response(
        requestOptions: o,
        data: {
          ..._window([], offset: 0, total: 0),
          'schemaVersion': 2,
          'creditItems': [
            credit('contribution:one', 'weather_reward', '150000000'),
            credit('forecast:two', 'forecast_reward', '18446744073709551615'),
            credit(
              'forecast:three',
              'forecast_reward',
              '340282366920938463463374607431768211455',
            ),
          ],
          'creditNextCursor': null,
        },
      ),
    );
    await _pumpWallet(tester, backend);
    expect(find.text('Received'), findsNWidgets(3));
    expect(find.text('Weather reward'), findsOneWidget);
    expect(find.text('Forecast reward'), findsNWidgets(2));
    expect(find.text('+1.5 WRF'), findsOneWidget);
    expect(find.text('+184467440737.09551615 WRF'), findsOneWidget);
    expect(
      find.text('+3402823669209384634633746074317.68211455 WRF'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('contribution:one')), findsOneWidget);
    expect(find.byKey(const ValueKey('forecast:two')), findsOneWidget);
    expect(find.textContaining('Block 0'), findsNothing);
    expect(find.text('Reward payment dates are unavailable'), findsOneWidget);
  });

  testWidgets('one reward in both items and creditItems renders once', (
    tester,
  ) async {
    final dup = credit('contribution:dup', 'weather_reward', '150000000');
    final backend = _Backend(
      (o) => Response(
        requestOptions: o,
        data: {
          ..._window([dup], offset: 0, total: 1),
          'schemaVersion': 2,
          'creditItems': [dup],
          'creditNextCursor': null,
        },
      ),
    );
    await _pumpWallet(tester, backend);
    expect(find.byKey(const ValueKey('contribution:dup')), findsOneWidget);
    expect(find.text('+1.5 WRF'), findsOneWidget);
  });

  testWidgets('a cursor the edge would refuse is never sent', (tester) async {
    final backend = _Backend(
      (o) => Response(
        requestOptions: o,
        data: {
          ..._window([], offset: 0, total: 0),
          'schemaVersion': 2,
          'creditItems': [
            credit('forecast:one', 'forecast_reward', '100000001'),
            credit('forecast:one', 'forecast_reward', '100000001'),
          ],
          'creditNextCursor': 'commit&first',
        },
      ),
    );
    await _pumpWallet(tester, backend);
    expect(backend.historyRequests, hasLength(1));
    expect(find.text('+1.00000001 WRF'), findsOneWidget);
    expect(find.byKey(const ValueKey('forecast:one')), findsOneWidget);
    expect(find.byKey(const Key('wallet-credits-truncated')), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets(
    'unpaid or invalid credits and unknown direction cannot claim receipt',
    (tester) async {
      final backend = _Backend(
        (o) => Response(
          requestOptions: o,
          data: {
            ..._window(
              [
                {
                  ..._item('unknown', from: _other),
                  'settlement': 'included',
                  'type': 'transfer',
                  'direction': 'unknown',
                  'amountBaseUnits': '100000000',
                },
                {
                  ..._item('self', from: _own),
                  'to': _own,
                  'settlement': 'included',
                  'type': 'transfer',
                  'direction': 'self',
                  'amountBaseUnits': '100000000',
                },
                {
                  ..._item('numeric', from: _other),
                  'settlement': 'included',
                  'type': 'transfer',
                  'direction': 'received',
                  'amountBaseUnits': 100000000,
                },
              ],
              offset: 0,
              total: 3,
            ),
            'schemaVersion': 2,
            'creditItems': [
              {
                ...credit('forecast:pending', 'forecast_reward', '100000000'),
                'settlement': 'pending',
              },
              credit('achievement:one', 'achievement_reward', '100000000'),
              {
                ...credit('forecast:foreign', 'forecast_reward', '100000000'),
                'to': _other,
              },
              credit('forecast:zero', 'forecast_reward', '0'),
              {
                ...credit('forecast:null-id', 'forecast_reward', '100000000'),
                'eventId': null,
              },
              {
                ...credit('forecast:numeric', 'forecast_reward', '1'),
                'amountBaseUnits': 100000000,
              },
              credit('forecast:fraction', 'forecast_reward', '1.5'),
              credit(
                'forecast:overflow',
                'forecast_reward',
                '340282366920938463463374607431768211456',
              ),
            ],
            'creditNextCursor': null,
          },
        ),
      );
      await _pumpWallet(tester, backend);
      expect(find.text('Forecast reward'), findsNothing);
      expect(find.text('Self transfer'), findsOneWidget);
      expect(find.text('Transaction'), findsOneWidget);
      expect(find.text('Amount not reported'), findsOneWidget);
      expect(find.text('+1 WRF'), findsNothing);
    },
  );
  testWidgets('null event IDs use hash or indexed keys without crashing', (
    tester,
  ) async {
    final backend = _Backend(
      (o) =>
          Response(requestOptions: o, data: _window([], offset: 0, total: 0)),
    );
    await _pumpWallet(
      tester,
      backend,
      transactions: const TransactionsState(
        items: [],
        hasMore: false,
        loadingMore: false,
        complete: false,
        credits: [
          TransactionModel(
            hash: '',
            from: '',
            value: '100000000',
            direction: 'incoming',
            type: 'forecast_reward',
            settlement: 'paid',
          ),
          TransactionModel(
            hash: '',
            from: '',
            value: '200000000',
            direction: 'incoming',
            type: 'forecast_reward',
            settlement: 'paid',
          ),
          TransactionModel(
            hash: 'payment:known',
            from: '',
            value: '300000000',
            direction: 'incoming',
            type: 'forecast_reward',
            settlement: 'paid',
          ),
        ],
      ),
    );
    expect(
      find.byKey(const ValueKey('credit:forecast_reward:0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('credit:forecast_reward:1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('payment:known')), findsOneWidget);
    expect(find.text('Received'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'v2 received transfers use canonical direction and exact decimals',
    (tester) async {
      final backend = _Backend(
        (o) => Response(
          requestOptions: o,
          data: {
            ..._window(
              [
                {
                  ..._item('tx:received', from: _other),
                  'eventId': 'transaction:received',
                  'to': _own,
                  'direction': 'received',
                  'kind': 'transfer',
                  'settlement': 'included',
                  'amountBaseUnits': '1',
                },
                {
                  ..._item('tx:sent', from: _own),
                  'eventId': 'transaction:sent',
                  'to': _other,
                  'direction': 'sent',
                  'kind': 'transfer',
                  'settlement': 'included',
                  'amountBaseUnits': '18446744073709551615',
                },
                {
                  ..._item('tx:pending', from: _other),
                  'eventId': 'transaction:pending',
                  'to': _own,
                  'direction': 'received',
                  'kind': 'transfer',
                  'settlement': 'pending',
                  'amountBaseUnits': '100000000',
                },
              ],
              offset: 0,
              total: 3,
            ),
            'schemaVersion': 2,
            'creditItems': [],
            'creditNextCursor': null,
          },
        ),
      );
      await _pumpWallet(tester, backend);
      expect(find.text('+0.00000001 WRF'), findsOneWidget);
      expect(find.text('-184467440737.09551615 WRF'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction:received')),
        findsOneWidget,
      );
      expect(find.text('Received'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Transaction'), findsOneWidget);
      expect(find.text('+1 WRF'), findsNothing);
    },
  );

  group('the public edge', () {
    // ~/r888/ct101-web4/build/edge/public_onboarding.caddy,
    // @public_readonly_wallet_transactions. Anything else gets a 404.
    final admitted = RegExp(
      r'^limit=([1-9]|[1-4][0-9]|50)&offset=[0-9]{1,6}'
      r'(&creditLimit=([1-9]|[1-9][0-9]|100))?(&creditAfter=[0-9a-f]{64})?$',
    );
    final cursor = 'ab' * 32;
    final path = RegExp(r'^/wallet/0x[0-9A-Fa-f]{40}/transactions$');

    testWidgets('admits every history read, first page and load more', (
      tester,
    ) async {
      final backend = _Backend((o) {
        final offset = int.parse(o.uri.queryParameters['offset']!);
        return Response(
          requestOptions: o,
          data: {
            ..._window(
              [
                for (var i = 0; i < 50; i++)
                  _item('0x$offset-$i', from: _other),
              ],
              offset: offset,
              total: 120,
            ),
            'schemaVersion': 2,
            'creditItems': [credit('forecast:$offset', 'forecast_reward', '1')],
            'creditNextCursor': cursor,
          },
        );
      });
      final container = await _pumpWallet(tester, backend);
      unawaited(container.read(transactionsProvider.notifier).loadMore());
      await _settle(tester);

      expect(backend.historyRequests, hasLength(2));
      expect(
        backend.historyRequests.first.query,
        'limit=50&offset=0&creditLimit=100',
      );
      expect(
        backend.historyRequests.last.query,
        'limit=50&offset=50&creditLimit=100&creditAfter=$cursor',
      );
      for (final uri in backend.historyRequests) {
        expect(uri.query, matches(admitted));
        expect(uri.path, matches(path));
      }
    });

    for (final (name, status, body) in <(String, int, Object?)>[
      ('edge 404', 404, 'Not found'),
      ('server error', 500, null),
      ('answer with no list', 200, '<html>not json</html>'),
      ('object with no list', 200, const {'ok': true}),
    ]) {
      testWidgets('$name shows an error with Retry, not an empty history', (
        tester,
      ) async {
        var fail = true;
        final backend = _Backend(
          (o) => fail
              ? Response(requestOptions: o, statusCode: status, data: body)
              : Response(
                  requestOptions: o,
                  data: _window(
                    [_item('0xok', from: _other)],
                    offset: 0,
                    total: 1,
                  ),
                ),
        );
        await _pumpWallet(tester, backend);
        // Past the provider's retries of a failure that may pass.
        await tester.pump(const Duration(minutes: 2));
        await _settle(tester);

        expect(find.byKey(const Key('wallet-history-error')), findsOneWidget);
        expect(find.text('No activity in this page'), findsNothing);
        expect(find.textContaining('0 total'), findsNothing);

        fail = false;
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        expect(find.byKey(const Key('wallet-history-error')), findsNothing);
        expect(find.byType(TransactionTile), findsOneWidget);
      });
    }

    testWidgets('a real empty list still says so', (tester) async {
      final backend = _Backend(
        (o) =>
            Response(requestOptions: o, data: _window([], offset: 0, total: 0)),
      );
      await _pumpWallet(tester, backend);
      expect(find.text('No activity in this page'), findsOneWidget);
      expect(find.byKey(const Key('wallet-history-error')), findsNothing);
    });
  });

  // The exact rows backend historyItem(tx, 2) builds from core4's
  // address_transaction_read_summary and paid_credit_summary.
  testWidgets('real v2 rows: transfer, faucet, operation and reward', (
    tester,
  ) async {
    Map<String, dynamic> row({
      required String txId,
      required int height,
      required String? type,
      required String? from,
      required String? to,
      required String? amount,
      required String direction,
      required String? kind,
    }) => {
      'txId': txId,
      'blockHeight': height,
      'type': kind ?? type,
      'from': from,
      'to': to,
      'amount': amount,
      'amountBaseUnits': amount,
      'eventId': 'transaction:$txId',
      'timestamp': null,
      'direction': direction,
      'counterparty': direction == 'sent' ? to : from,
      'kind': kind,
      'settlement': 'included',
    };
    final sentId = List.filled(64, 'a').join();
    final backend = _Backend(
      (o) => Response(
        requestOptions: o,
        data: {
          'schemaVersion': 2,
          'items': [
            row(
              txId: sentId,
              height: 11768,
              type: 'Transfer',
              from: _own,
              to: _other,
              amount: '50000000',
              direction: 'sent',
              kind: 'transfer',
            ),
            row(
              txId: List.filled(64, 'b').join(),
              height: 11000,
              type: 'Transfer',
              from: _other,
              to: _own,
              amount: '100000000000',
              direction: 'received',
              kind: 'transfer',
            ),
            row(
              txId: List.filled(64, 'c').join(),
              height: 11500,
              type: 'ContributionCommit',
              from: _own,
              to: null,
              amount: null,
              direction: 'unknown',
              kind: null,
            ),
          ],
          'creditItems': [
            {
              'txId': null,
              'blockHeight': null,
              'type': 'weather_reward',
              'from': null,
              'to': _own,
              'amount': '12500000',
              'amountBaseUnits': '12500000',
              'eventId': 'contribution:${List.filled(64, 'd').join()}',
              'timestamp': null,
              'direction': 'received',
              'counterparty': null,
              'kind': 'weather_reward',
              'settlement': 'paid',
            },
          ],
          'creditNextCursor': 'more',
          'creditTotal': null,
          'windowStartHeight': 1,
          'source': 'core4',
          'complete': false,
          'limit': 50,
          'offset': 0,
          'totalInWindow': 3,
        },
      ),
    );
    final container = await _pumpWallet(tester, backend);
    final state = container.read(transactionsProvider).requireValue;

    final sent = state.items.first;
    expect(sent.hash, sentId);
    expect(sent.blockNumber, 11768);
    expect(sent.direction, 'outgoing');
    expect(sent.value, '50000000');
    expect(sent.to, _other);
    expect(sent.settlement, 'included');
    expect(state.items[1].direction, 'incoming');
    expect(state.items[1].value, '100000000000');
    expect(state.items[2].value, isNull);
    expect(state.items[2].type, 'ContributionCommit');
    expect(state.credits.single.value, '12500000');
    expect(state.credits.single.type, 'weather_reward');

    expect(find.text('-0.5 WRF'), findsOneWidget);
    expect(find.text('+1000 WRF'), findsOneWidget);
    expect(find.text('+0.125 WRF'), findsOneWidget);
    expect(find.text('Paid rewards'), findsOneWidget);
    expect(find.byKey(const Key('wallet-credits-truncated')), findsOneWidget);
  });
}
