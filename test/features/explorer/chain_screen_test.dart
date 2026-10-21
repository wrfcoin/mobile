import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/features/explorer/data/explorer_models.dart';
import 'package:wrfcoin_mobile/features/explorer/data/explorer_remote_datasource.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:go_router/go_router.dart';

import '../../test_helpers/fakes.dart';
import 'package:wrfcoin_mobile/features/explorer/presentation/providers/chain_explorer_provider.dart';
import 'package:wrfcoin_mobile/features/explorer/presentation/screens/chain_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';

class _Backend {
  _Backend({this.summary, this.blocks, this.failSummary = false, this.failBlocks = false});

  Map<String, dynamic>? summary;
  List<Map<String, dynamic>>? blocks;
  bool failSummary;
  bool failBlocks;
  Map<String, dynamic>? detail;
  int summaryCalls = 0;
  int blockCalls = 0;
  final List<String> paths = [];

  Dio dio() {
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          paths.add(o.path);
          DioException fail() => DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: o, statusCode: 503),
          );
          if (o.path == '/explorer/summary') {
            summaryCalls++;
            if (failSummary) return h.reject(fail());
            return h.resolve(Response(requestOptions: o, data: summary));
          }
          if (o.path == '/blockchain/blocks') {
            blockCalls++;
            if (failBlocks) return h.reject(fail());
            return h.resolve(Response(requestOptions: o, data: {'blocks': blocks}));
          }
          if (o.path.startsWith('/blockchain/blocks/')) {
            return h.resolve(
              Response(
                requestOptions: o,
                data: detail ?? {
                  'height': int.parse(o.path.split('/').last),
                  'hash': '0xabcdef0123456789abcdef',
                  'previousHash': '0x1111111111111111',
                  'timestamp': '2026-10-01T12:00:00.000Z',
                  'transactions': [],
                  'transactionCount': 2,
                },
              ),
            );
          }
          h.reject(fail());
        },
      ),
    );
    return dio;
  }
}

Map<String, dynamic> _ok({
  String status = 'producing',
  int? height = 500,
  int? tipAge = 30,
  double? bpm = 1.0,
  int? peers = 4,
  bool? funded = true,
}) => {
  'state': 'ok',
  'status': status,
  'height': height,
  'tipAgeSeconds': tipAge,
  'blocksPerMinute': bpm,
  'peerCount': peers,
  'faucetFunded': funded,
};

List<Map<String, dynamic>> _blocks([int top = 500, int n = 15]) => [
  for (var i = 0; i < n; i++)
    {
      'height': top - i,
      'hash': '0xhash${top - i}abcdefabcdef',
      'previousHash': '0xprev',
      'timestamp': '2026-10-01T12:00:00.000Z',
      'transactions': i,
    },
];

class _FakeWallet extends WalletNotifier {
  _FakeWallet(this.model);
  final WalletModel? model;
  @override
  Future<WalletModel?> build() async => model;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Backend backend, {
  WalletModel? wallet,
  Duration poll = const Duration(seconds: 10),
  Widget Function(Widget child)? wrap,
}) async {
  final container = ProviderContainer(
    overrides: [
      explorerRemoteDataSourceProvider.overrideWithValue(
        ExplorerRemoteDataSource(backend.dio()),
      ),
      chainPollIntervalProvider.overrideWithValue(poll),
      walletProvider.overrideWith(() => _FakeWallet(wallet)),
      // These tests are about layout and polling; the session gate has its own
      // tests below that use the real provider.
      chainAccountVisibleProvider.overrideWith((ref) async => true),
    ],
  );
  addTearDown(container.dispose);
  final screen = wrap == null ? const ChainScreen() : wrap(const ChainScreen());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: MaterialApp(home: screen)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('producing: pill, height, blocks/min, tip age, peers and faucet', (tester) async {
    await _pump(tester, _Backend(summary: _ok(), blocks: _blocks()));
    expect(find.text('Producing'), findsOneWidget);
    expect(_text(tester, 'chain-height'), '500');
    expect(_text(tester, 'chain-bpm'), '1.0');
    expect(_text(tester, 'chain-tip-age'), '30 s');
    expect(_text(tester, 'chain-peers'), '4');
    expect(_text(tester, 'chain-faucet'), 'Funded');
  });

  testWidgets('stalled: the pill says Stalled and the tip age is shown', (tester) async {
    await _pump(tester, _Backend(summary: _ok(status: 'stalled', tipAge: 400), blocks: _blocks()));
    expect(find.text('Stalled'), findsOneWidget);
    expect(_text(tester, 'chain-tip-age'), '6 min 40 s');
  });

  testWidgets('degraded (backend says so): pill Degraded and every stat is —', (tester) async {
    await _pump(
      tester,
      _Backend(summary: {'state': 'degraded', 'status': 'unknown', 'height': null}, blocks: _blocks()),
    );
    expect(find.text('Degraded'), findsOneWidget);
    for (final k in ['chain-height', 'chain-bpm', 'chain-tip-age', 'chain-peers']) {
      expect(_text(tester, k), '—');
    }
    expect(_text(tester, 'chain-faucet'), 'Unknown');
  });

  testWidgets('degraded (request failed): not an error screen, no fake numbers', (tester) async {
    await _pump(tester, _Backend(failSummary: true, failBlocks: true));
    expect(find.text('Degraded'), findsOneWidget);
    expect(_text(tester, 'chain-height'), '—');
    expect(find.byKey(const Key('chain-blocks-unavailable')), findsOneWidget);
    expect(find.textContaining('Something Went Wrong'), findsNothing);
  });

  testWidgets('a null field shows — and faucetFunded null is Unknown, false is Empty', (tester) async {
    await _pump(
      tester,
      _Backend(summary: _ok(bpm: null, peers: null, funded: null, tipAge: null), blocks: _blocks()),
    );
    expect(_text(tester, 'chain-bpm'), '—');
    expect(_text(tester, 'chain-peers'), '—');
    expect(_text(tester, 'chain-tip-age'), '—');
    expect(_text(tester, 'chain-faucet'), 'Unknown');
    expect(find.text('Producing'), findsOneWidget); // status itself was reported
  });

  testWidgets('faucetFunded false reads Empty, not Unknown', (tester) async {
    await _pump(tester, _Backend(summary: _ok(funded: false), blocks: _blocks()));
    expect(_text(tester, 'chain-faucet'), 'Empty');
  });

  testWidgets('recent blocks request limit 15; tapping a block opens its detail', (tester) async {
    final backend = _Backend(summary: _ok(), blocks: _blocks());
    await _pump(tester, backend);
    expect(find.byKey(const Key('chain-block-500')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chain-block-500')));
    await tester.pumpAndSettle();
    expect(find.text('Block #500'), findsOneWidget);
    expect(backend.paths, contains('/blockchain/blocks/500'));
    expect(find.text('2'), findsOneWidget); // transaction count
  });

  testWidgets('no wallet: no My account card', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester, _Backend(summary: _ok(), blocks: _blocks()));
    expect(find.byKey(const Key('chain-my-account')), findsNothing);
  });

  testWidgets('signed in: My account shows balance and masked address', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const wallet = WalletModel(
      address: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      balance: '150000000',
    );
    await _pump(tester, _Backend(summary: _ok(), blocks: _blocks()), wallet: wallet);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('chain-my-account')), findsOneWidget);
    expect(find.text('1.5 WRF'), findsOneWidget);
    expect(find.text('0xaaaa...aaaa'), findsOneWidget);
  });

  testWidgets('polls every 10 s while visible and never faster than 10 s', (tester) async {
    final backend = _Backend(summary: _ok(), blocks: _blocks());
    await _pump(tester, backend, poll: const Duration(seconds: 1)); // clamped up to 10 s
    final first = backend.summaryCalls;
    await tester.pump(const Duration(seconds: 9));
    expect(backend.summaryCalls, first);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(backend.summaryCalls, first + 1);
  });

  testWidgets('the timer stops in the background and resumes (with a refresh) in the foreground', (tester) async {
    final backend = _Backend(summary: _ok(), blocks: _blocks());
    await _pump(tester, backend);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final paused = backend.summaryCalls;
    await tester.pump(const Duration(seconds: 60));
    expect(backend.summaryCalls, paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(backend.summaryCalls, paused + 1);
  });

  testWidgets('the timer is cancelled on dispose (no pending timers, no further requests)', (tester) async {
    final backend = _Backend(summary: _ok(), blocks: _blocks());
    await _pump(tester, backend);
    await tester.pumpWidget(const SizedBox());
    final after = backend.summaryCalls;
    await tester.pump(const Duration(seconds: 60));
    expect(backend.summaryCalls, after);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('no polling while another page covers it', (tester) async {
    final backend = _Backend(summary: _ok(), blocks: _blocks());
    final navKey = GlobalKey<NavigatorState>();
    final container = ProviderContainer(
      overrides: [
        explorerRemoteDataSourceProvider.overrideWithValue(ExplorerRemoteDataSource(backend.dio())),
        chainPollIntervalProvider.overrideWithValue(const Duration(seconds: 10)),
        walletProvider.overrideWith(() => _FakeWallet(null)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(navigatorKey: navKey, home: const ChainScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('covering'))));
    await tester.pumpAndSettle();
    final covered = backend.summaryCalls;
    await tester.pump(const Duration(seconds: 35));
    expect(backend.summaryCalls, covered);
  });

  testWidgets('pull to refresh re-reads summary and blocks', (tester) async {
    final backend = _Backend(summary: _ok(), blocks: _blocks());
    await _pump(tester, backend);
    final s = backend.summaryCalls;
    final b = backend.blockCalls;
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(backend.summaryCalls, s + 1);
    expect(backend.blockCalls, b + 1);
  });

  group('session gate on the My account card (P1)', () {
    const wallet = WalletModel(
      address: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      balance: '150000000',
    );

    testWidgets('warm cache, then sign-out / expiry: the private card disappears without a login', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final storage = InMemoryKeyValueStorage();
      final keys = KeyManager(biometric: BiometricService(client: FakeLocalAuthClient()), storage: storage);
      await keys.storeAuthSession(jwt: 'jwt-token', expiresInSeconds: 3600);
      final handoff = AuthHandoffController();
      final backend = _Backend(summary: _ok(), blocks: _blocks());
      final container = ProviderContainer(
        overrides: [
          explorerRemoteDataSourceProvider.overrideWithValue(ExplorerRemoteDataSource(backend.dio())),
          chainPollIntervalProvider.overrideWithValue(const Duration(seconds: 10)),
          walletProvider.overrideWith(() => _FakeWallet(wallet)), // the warm cache stays populated
          keyManagerProvider.overrideWithValue(keys),
          authHandoffControllerProvider.overrideWith((ref) => handoff),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/wallet/chain',
        routes: [GoRoute(path: '/wallet/chain', builder: (_, _) => const ChainScreen())],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('chain-my-account')), findsOneWidget);

      // Sign-out: session cleared and the handoff raised; the wallet cache is untouched.
      await keys.clearAccessToken();
      handoff.requireWalletConnect(reason: AuthHandoffReason.sessionExpired, message: 'Session expired.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(walletProvider).value, isNotNull); // still cached
      expect(find.byKey(const Key('chain-my-account')), findsNothing);
      expect(find.text('1.5 WRF'), findsNothing);
      // No wallet-login or nonce request was made by the page.
      expect(backend.paths.where((p) => p.contains('auth') || p.contains('wallet')), isEmpty);
    });

    testWidgets('no stored session and no handoff yet: the card is hidden', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final keys = KeyManager(biometric: BiometricService(client: FakeLocalAuthClient()), storage: InMemoryKeyValueStorage());
      final container = ProviderContainer(
        overrides: [
          explorerRemoteDataSourceProvider.overrideWithValue(ExplorerRemoteDataSource(_Backend(summary: _ok(), blocks: _blocks()).dio())),
          walletProvider.overrideWith(() => _FakeWallet(wallet)),
          keyManagerProvider.overrideWithValue(keys),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: ChainScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('chain-my-account')), findsNothing);
    });
  });

  group('visibility and cancellation (P2a/P2b)', () {
    testWidgets('resume while another page covers the Chain page makes no request', (tester) async {
      final backend = _Backend(summary: _ok(), blocks: _blocks());
      final navKey = GlobalKey<NavigatorState>();
      final container = ProviderContainer(overrides: [
        explorerRemoteDataSourceProvider.overrideWithValue(ExplorerRemoteDataSource(backend.dio())),
        chainPollIntervalProvider.overrideWithValue(const Duration(seconds: 10)),
        walletProvider.overrideWith(() => _FakeWallet(null)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(navigatorKey: navKey, home: const ChainScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('covering'))));
      await tester.pumpAndSettle();
      final before = backend.summaryCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 30));
      expect(backend.summaryCalls, before);
    });

    Future<({ApiClient client, List<String> requests})> realClient() async {
      final requests = <String>[];
      final client = ApiClient();
      client.dio.httpClientAdapter = _Always503Adapter(requests);
      return (client: client, requests: requests);
    }

    testWidgets('real ApiClient 503 retries: pausing cancels in-flight reads and pending retries', (tester) async {
      final real = await realClient();
      final container = ProviderContainer(overrides: [
        explorerRemoteDataSourceProvider.overrideWithValue(ExplorerRemoteDataSource(real.client.dio)),
        chainPollIntervalProvider.overrideWithValue(const Duration(seconds: 10)),
        walletProvider.overrideWith(() => _FakeWallet(null)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: ChainScreen())));
      await tester.pump(const Duration(milliseconds: 100)); // both reads hit the adapter and fail with 503
      expect(real.requests.length, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 30)); // well past every retry delay
      expect(real.requests.length, 2, reason: 'no retry may reach the adapter after pause');
    });

    testWidgets('real ApiClient 503 retries: disposing the page cancels pending retries', (tester) async {
      final real = await realClient();
      final container = ProviderContainer(overrides: [
        explorerRemoteDataSourceProvider.overrideWithValue(ExplorerRemoteDataSource(real.client.dio)),
        chainPollIntervalProvider.overrideWithValue(const Duration(seconds: 10)),
        walletProvider.overrideWith(() => _FakeWallet(null)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: ChainScreen())));
      await tester.pump(const Duration(milliseconds: 100));
      expect(real.requests.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
      expect(real.requests.length, 2, reason: 'no retry may reach the adapter after dispose');
    });

    testWidgets('real ApiClient 503 retries: covering the page with another route cancels pending retries', (tester) async {
      final real = await realClient();
      final navKey = GlobalKey<NavigatorState>();
      final container = ProviderContainer(overrides: [
        explorerRemoteDataSourceProvider.overrideWithValue(ExplorerRemoteDataSource(real.client.dio)),
        chainPollIntervalProvider.overrideWithValue(const Duration(seconds: 10)),
        walletProvider.overrideWith(() => _FakeWallet(null)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(navigatorKey: navKey, home: const ChainScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 100)); // two reads failed with 503; retries are pending
      expect(real.requests.length, 2);
      navKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('covering'))));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30)); // well past every retry delay
      expect(real.requests.length, 2, reason: 'no retry may reach the adapter while the page is covered');
    });

    testWidgets('a read cancelled by pausing is discarded: the page keeps what it had', (tester) async {
      final backend = _Backend(summary: _ok(), blocks: _blocks());
      await _pump(tester, backend);
      expect(find.text('Producing'), findsOneWidget);
      backend.summary = {'state': 'degraded'};
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Producing'), findsOneWidget);
    });
  });

  group('re-entry and block-detail lifecycle', () {
    ProviderContainer realContainer(_PathAdapter adapter) {
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;
      final container = ProviderContainer(overrides: [
        explorerRemoteDataSourceProvider.overrideWithValue(ExplorerRemoteDataSource(client.dio)),
        chainPollIntervalProvider.overrideWithValue(const Duration(seconds: 10)),
        walletProvider.overrideWith(() => _FakeWallet(null)),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    testWidgets('Chain -> elsewhere -> Chain reads afresh (the scope is not left cancelled)', (tester) async {
      final adapter = _PathAdapter({'/explorer/summary': 200, '/blockchain/blocks': 200});
      final container = realContainer(adapter);
      final router = GoRouter(initialLocation: '/chain', routes: [
        GoRoute(path: '/chain', builder: (_, _) => const ChainScreen()),
        GoRoute(path: '/other', builder: (_, _) => const Scaffold(body: Text('elsewhere'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(adapter.count('/explorer/summary'), 1);
      router.go('/other');
      await tester.pumpAndSettle();
      expect(find.text('elsewhere'), findsOneWidget);
      router.go('/chain');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(adapter.count('/explorer/summary'), 2, reason: 'the second visit must read');
      expect(adapter.count('/blockchain/blocks'), 2);
      expect(find.text('Producing'), findsOneWidget);
      // and the second visit still cancels on its own exit
      router.go('/other');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      expect(adapter.count('/explorer/summary'), 2);
    });

    Future<_PathAdapter> openDetail(WidgetTester tester, {int detailStatus = 503}) async {
      final adapter = _PathAdapter({'/explorer/summary': 200, '/blockchain/blocks': 200, '/blockchain/blocks/500': detailStatus});
      final container = realContainer(adapter);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: ChainScreen())));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.byKey(const Key('chain-block-500')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(adapter.count('/blockchain/blocks/500'), 1);
      return adapter;
    }

    testWidgets('detail 503: pausing the app cancels the pending retry', (tester) async {
      final adapter = await openDetail(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(adapter.count('/blockchain/blocks/500'), 1);
    });

    testWidgets('detail 503: leaving the page with the sheet open cancels the pending retry', (tester) async {
      final adapter = await openDetail(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
      expect(adapter.count('/blockchain/blocks/500'), 1);
    });

    testWidgets('detail 503: closing the sheet cancels the pending retry', (tester) async {
      final adapter = await openDetail(tester);
      await tester.tapAt(const Offset(5, 5)); // the barrier
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      expect(adapter.count('/blockchain/blocks/500'), 1);
    });

    testWidgets('a foreground detail read still works through the real client', (tester) async {
      final adapter = _PathAdapter({'/explorer/summary': 200, '/blockchain/blocks': 200, '/blockchain/blocks/500': 200});
      final container = realContainer(adapter);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: ChainScreen())));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.byKey(const Key('chain-block-500')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Block #500'), findsOneWidget);
      expect(adapter.count('/blockchain/blocks/500'), 1);
    });
  });

  group('parsing honesty (P2c)', () {
    test('an explicit null transactionCount beside a projected array stays unknown', () {
      final b = ChainBlock.fromJson({'height': 500, 'transactionCount': null, 'transactions': []});
      expect(b.transactionCount, isNull);
    });
    test('a legacy list count is used only when transactionCount is absent', () {
      expect(ChainBlock.fromJson({'height': 1, 'transactions': 7}).transactionCount, 7);
      expect(ChainBlock.fromJson({'height': 1, 'transactionCount': 3, 'transactions': []}).transactionCount, 3);
      expect(ChainBlock.fromJson({'height': 1, 'transactions': []}).transactionCount, isNull);
    });
    test('NaN and Infinity strings are not numbers', () {
      for (final bad in ['NaN', 'Infinity', '-Infinity', double.nan, double.infinity]) {
        final s = ExplorerSummary.fromJson({'state': 'ok', 'status': 'producing', 'blocksPerMinute': bad, 'height': 5});
        expect(s.blocksPerMinute, isNull, reason: '$bad');
      }
      expect(ExplorerSummary.fromJson({'state': 'ok', 'blocksPerMinute': '1.5'}).blocksPerMinute, 1.5);
    });
    testWidgets('the detail sheet shows — for an unreported transaction count', (tester) async {
      final backend = _Backend(summary: _ok(), blocks: _blocks())
        ..detail = {'height': 500, 'hash': '0xabcdef0123456789abcdef', 'transactionCount': null, 'transactions': []};
      await _pump(tester, backend);
      await tester.tap(find.byKey(const Key('chain-block-500')));
      await tester.pumpAndSettle();
      final row = find.ancestor(of: find.text('Transactions'), matching: find.byType(Row));
      expect(find.descendant(of: row, matching: find.text('—')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('0')), findsNothing);
    });
  });
}

class _Always503Adapter implements HttpClientAdapter {
  _Always503Adapter(this.requests);
  final List<String> requests;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options.path);
    return ResponseBody.fromString('{}', 503, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// Real-client adapter answering per path: [status] by path, with a valid body for 200s.
class _PathAdapter implements HttpClientAdapter {
  _PathAdapter(this.status);
  final Map<String, int> status;
  final List<String> paths = [];
  int count(String path) => paths.where((p) => p == path).length;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.path);
    final code = status[options.path] ?? 404;
    final Object body;
    if (options.path == '/explorer/summary') {
      body = _ok();
    } else if (options.path == '/blockchain/blocks') {
      body = {'blocks': _blocks()};
    } else if (options.path.startsWith('/blockchain/blocks/')) {
      body = {'height': 500, 'hash': '0xabcdef0123456789abcdef', 'transactionCount': 2, 'transactions': []};
    } else {
      body = {};
    }
    return ResponseBody.fromString(code == 200 ? jsonEncode(body) : '{}', code, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}
