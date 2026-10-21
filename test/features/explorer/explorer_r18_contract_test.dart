import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/explorer/data/explorer_models.dart';
import 'package:wrfcoin_mobile/features/explorer/data/explorer_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/explorer/presentation/providers/chain_explorer_provider.dart';
import 'package:wrfcoin_mobile/features/explorer/presentation/screens/chain_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';

// backend#1387: server/routes/explorer-routes.js flat summary; blockchain-routes.js
// anonymous blocks window <= 30. Public synthetic payloads, no HTTP transport.
class _Wire implements HttpClientAdapter {
  int summaryStatus = 200;
  int blocksStatus = 200;
  Object summary = {
    'state': 'ok',
    'status': 'producing',
    'height': 500,
    'tipAgeSeconds': 30,
    'blocksPerMinute': 1.0,
    'blocksSampled': 30,
    'stallThresholdSeconds': 180,
    'peerCount': 4,
    'faucetFunded': true,
    'generatedAt': '2026-10-02T12:00:00.000Z',
  };
  List<Object> blocks = [];
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final isSummary = options.uri.path == '/api/explorer/summary';
    final isBlocks = options.uri.path == '/api/blockchain/blocks';
    final status = isSummary
        ? summaryStatus
        : isBlocks
        ? blocksStatus
        : 404;
    final body = isSummary
        ? summary
        : isBlocks
        ? {
            'success': true,
            'blocks': blocks,
            'data': blocks,
            'total': 501,
            'pagination': {'limit': 15, 'offset': 0, 'hasNext': true},
          }
        : {'error': true};
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Dio dio() =>
      Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'))
        ..httpClientAdapter = this;
  @override
  void close({bool force = false}) {}
}

class _NoWallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => null;
}

void main() {
  test('default block read requests 15, orders newest first and bounds a larger response', () async {
    final wire = _Wire()
      ..blocks = [
        for (var height = 470; height <= 500; height++)
          {
            'height': height,
            'transactions': 0,
            'timestamp': '2026-10-02T12:00:00Z',
          },
      ];
    final blocks = await ExplorerRemoteDataSource(wire.dio())
        .fetchRecentBlocks();
    expect(wire.requests.single.uri.path, '/api/blockchain/blocks');
    expect(wire.requests.single.queryParameters, {'limit': 15});
    expect(wire.requests.single.headers.containsKey('Authorization'), isFalse);
    expect(blocks, hasLength(15));
    expect(blocks!.first.height, 500);
    expect(blocks.last.height, 486);
    expect(blocks.first.transactionCount, 0);
  });

  for (final (requested, bounded) in [
    (0, 1),
    (-1, 1),
    (31, 30),
    (1000000, 30),
  ]) {
    test(
      'anonymous block limit $requested stays within the backend 1–30 window',
      () async {
        final wire = _Wire();
        await ExplorerRemoteDataSource(wire.dio())
            .fetchRecentBlocks(limit: requested);
        expect(wire.requests.single.queryParameters['limit'], bounded);
      },
    );
  }

  test('negative block heights are refused locally', () async {
    final wire = _Wire();
    expect(await ExplorerRemoteDataSource(wire.dio()).fetchBlock(-1), isNull);
    expect(wire.requests, isEmpty);
  });

  for (final (status, empty) in [
    (200, false),
    (200, true),
    (400, false),
    (404, false),
    (500, false),
    (503, false),
  ]) {
    testWidgets(
      'Chain consumes real datasource HTTP $status empty=$empty without fabricated values',
      (tester) async {
        final wire = _Wire()
          ..summaryStatus = status
          ..blocksStatus = status;
        if (status == 200 && !empty) {
          wire.blocks = [
            {
              'height': 500,
              'transactions': 0,
              'timestamp': '2026-10-02T12:00:00Z',
            },
          ];
        }
        if (empty) {
          wire.summary = {
            'state': 'ok',
            'status': 'unknown',
            'height': null,
            'tipAgeSeconds': null,
            'blocksPerMinute': null,
            'peerCount': null,
            'faucetFunded': null,
          };
        }
        final container = ProviderContainer(
          overrides: [
            explorerRemoteDataSourceProvider.overrideWithValue(
              ExplorerRemoteDataSource(wire.dio()),
            ),
            walletProvider.overrideWith(() => _NoWallet()),
            chainAccountVisibleProvider.overrideWith((ref) async => false),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: ChainScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(wire.requests.map((r) => r.uri.path).toSet(), {
          '/api/explorer/summary',
          '/api/blockchain/blocks',
        });
        expect(
          find.descendant(
            of: find.byKey(const Key('chain-status-pill')),
            matching: find.text(
              status == 200 ? (empty ? 'Unknown' : 'Producing') : 'Degraded',
            ),
          ),
          findsOneWidget,
        );
        final height = tester
            .widget<Text>(find.byKey(const Key('chain-height')))
            .data;
        expect(height, status == 200 && !empty ? '500' : '—');
        final available = status == 200 && !empty;
        for (final (key, value) in [
          ('chain-bpm', available ? '1.0' : '—'),
          ('chain-tip-age', available ? '30 s' : '—'),
          ('chain-peers', available ? '4' : '—'),
          ('chain-faucet', available ? 'Funded' : 'Unknown'),
        ]) {
          expect(tester.widget<Text>(find.byKey(Key(key))).data, value);
        }
        expect(
          find.byKey(const Key('chain-block-500')),
          available ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('No blocks reported.'),
          status == 200 && empty ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('chain-blocks-unavailable')),
          status != 200 ? findsOneWidget : findsNothing,
        );
        expect(find.text('My account'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'empty and backend-degraded summaries preserve unknown metrics',
    () async {
      final wire = _Wire()
        ..summary = {
          'state': 'ok',
          'status': 'unknown',
          'height': null,
          'tipAgeSeconds': null,
          'blocksPerMinute': null,
          'peerCount': null,
          'faucetFunded': null,
        };
      final source = ExplorerRemoteDataSource(wire.dio());
      final empty = await source.fetchSummary();
      expect(empty.status, ChainStatus.unknown);
      expect(empty.height, isNull);
      expect(empty.blocksPerMinute, isNull);
      expect(empty.faucetFunded, isNull);
      expect(await source.fetchRecentBlocks(), isEmpty);
      wire.summary = {'state': 'degraded', 'status': 'unknown', 'height': null};
      expect((await source.fetchSummary()).status, ChainStatus.degraded);
    },
  );
}
