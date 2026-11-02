import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/network/public_read.dart';
import 'package:wrfcoin_mobile/features/network_nodes/data/repositories/network_nodes_repository.dart';
import 'package:wrfcoin_mobile/features/network_nodes/presentation/screens/network_nodes_screen.dart';

import '../../test_helpers/stub_http_adapter.dart';
import 'network_nodes_fixtures.dart';

Future<StubHttpAdapter> _pump(
  WidgetTester tester,
  (int, Object?)? Function(RequestOptions) answer,
) async {
  tester.view.physicalSize = const Size(390, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final adapter = StubHttpAdapter(answer);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        networkNodesRepositoryProvider.overrideWithValue(
          NetworkNodesRepository(stubDio(adapter)),
        ),
      ],
      child: const MaterialApp(home: NetworkNodesScreen()),
    ),
  );
  return adapter;
}

void main() {
  testWidgets('shows a loading state before the answer', (tester) async {
    await _pump(tester, (_) => (200, loadedNodes));
    expect(find.text('Reading the chain…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Reading the chain…'), findsNothing);
  });

  testWidgets('loaded: ladder, producers, bonds and attesters', (tester) async {
    final adapter = await _pump(tester, (_) => (200, loadedNodes));
    await tester.pumpAndSettle();

    expect(adapter.requests.single.path, '/network/nodes');
    expect(find.text('Height 11,601'), findsOneWidget);
    expect(find.text('2 bonded'), findsOneWidget);
    expect(find.text('2 seated'), findsOneWidget);
    expect(find.text('1 of 2 producing'), findsOneWidget);

    expect(find.text('producer-a'), findsOneWidget);
    expect(find.text('63 of 63 blocks'), findsOneWidget);
    expect(find.text('0 of 63 blocks'), findsOneWidget);
    expect(find.text('No block in this window'), findsOneWidget);
    expect(find.text('Paid in total: 1.50000000 WRF'), findsOneWidget);
    expect(find.text('Unnamed producer'), findsOneWidget);
    expect(find.textContaining('1 could not be read'), findsOneWidget);

    expect(find.text('node-one'), findsOneWidget);
    expect(find.text('Bond: 250.00000000 WRF'), findsOneWidget);
    expect(
      find.text('Latest payout: Pending 189.62962944 WRF · epoch 21'),
      findsOneWidget,
    );
    expect(find.text('Paid in total: 758.51851776 WRF'), findsOneWidget);
    expect(find.text('Jailed'), findsOneWidget);
    expect(
      find.text('2 seated · 2 must agree before a reading is paid'),
      findsOneWidget,
    );
    expect(find.textContaining('testnet · chain 888'), findsOneWidget);
  });

  testWidgets('a paid total the node did not give is never zero', (
    tester,
  ) async {
    await _pump(tester, (_) => (200, loadedNodes));
    await tester.pumpAndSettle();
    // producer-a, the unnamed producer and the unnamed node have no total.
    expect(find.text('Paid in total: Unavailable'), findsNWidgets(3));
    expect(find.text('Bond: Unavailable'), findsOneWidget);
    expect(find.text('Paid in total: 0.00000000 WRF'), findsNothing);
    expect(find.text('Unnamed node'), findsOneWidget);
    expect(find.text('Latest payout: none in the last epochs'), findsOneWidget);
  });

  testWidgets('empty: no bonds, and each failed section says so', (
    tester,
  ) async {
    await _pump(tester, (_) => (200, partlyUnavailableNodes));
    await tester.pumpAndSettle();

    expect(find.text('No bonded nodes found'), findsOneWidget);
    expect(find.text('0 bonded'), findsOneWidget);
    expect(find.text('Unavailable'), findsNWidgets(3));
    expect(
      find.text(
        'Producer activity unavailable: the chain node did not answer this part.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Attesters unavailable: the chain node did not answer this part.',
      ),
      findsOneWidget,
    );
  });

  group('error', () {
    const unavailable =
        'The producer and bonded-node list is unavailable right now';

    testWidgets('server failure says unavailable and retries', (tester) async {
      var up = false;
      final adapter = await _pump(
        tester,
        (_) => up ? (200, loadedNodes) : (502, {'success': false}),
      );
      await tester.pumpAndSettle();
      expect(find.text(unavailable), findsOneWidget);

      up = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(adapter.requests.length, 2);
      expect(find.text('producer-a'), findsOneWidget);
    });

    testWidgets('offline says unavailable', (tester) async {
      await _pump(tester, (_) => null);
      await tester.pumpAndSettle();
      expect(find.text(unavailable), findsOneWidget);
    });

    testWidgets('an HTML fallback page is not data', (tester) async {
      await _pump(tester, (_) => (200, '<!doctype html>'));
      await tester.pumpAndSettle();
      expect(find.text(unavailable), findsOneWidget);
    });

    testWidgets('404 says not switched on', (tester) async {
      await _pump(tester, (_) => (404, {'error': 'Not found'}));
      await tester.pumpAndSettle();
      expect(find.text('Not switched on yet'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('429 says wait and try again', (tester) async {
      await _pump(tester, (_) => (429, {'error': 'slow'}));
      await tester.pumpAndSettle();
      expect(find.textContaining('Too many requests'), findsOneWidget);
    });
  });

  test('publicWrf keeps every digit and refuses a non-number', () {
    expect(publicWrf('1234567890123'), '12,345.67890123 WRF');
    expect(publicWrf('5'), '0.00000005 WRF');
    expect(publicWrf('0'), '0.00000000 WRF');
    expect(publicWrf(null), isNull);
    expect(publicWrf('1.5'), isNull);
    expect(publicWrf('-1'), isNull);
  });
}
