import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/data/datasources/carbon_lottery_remote_datasource.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/data/models/carbon_lottery_models.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/data/repositories/carbon_lottery_repository_impl.dart';
import 'package:wrfcoin_mobile/features/carbon_lottery/presentation/screens/carbon_lottery_dashboard_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../test_helpers/fakes.dart';

const dashboard = {
  'epoch': 7,
  'jackpotCredits': '987',
  'projectedYieldCredits': '12',
  'totalDepositedCredits': '2000',
  'userDepositCredits': '31',
  'principalProtected': false,
  'history': <Object>[],
};

class _Transport implements HttpClientAdapter {
  final int? failure;
  final Object? payload;
  final requests = <RequestOptions>[];
  _Transport(this.failure, {this.payload});
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    final fail = options.method == 'POST' || payload == null;
    if (fail && failure == 0) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(fail ? {'message': 'Lottery service unavailable'} : payload),
      fail ? failure ?? 200 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

CarbonLotteryRepositoryImpl _repo(_Transport transport) =>
    CarbonLotteryRepositoryImpl(
      CarbonLotteryRemoteDataSource(
        Dio(BaseOptions(baseUrl: 'https://lottery.invalid'))
          ..httpClientAdapter = transport,
      ),
    );

Future<void> _mount(
  WidgetTester tester,
  _Transport transport, {
  bool wallet = true,
}) async {
  final storage = InMemoryKeyValueStorage();
  if (wallet) {
    await storage.write(key: 'wrf_address', value: 'synthetic-wallet');
  }
  final biometric = BiometricService(client: FakeLocalAuthClient());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        carbonLotteryRepositoryProvider.overrideWithValue(_repo(transport)),
        keyManagerProvider.overrideWithValue(
          KeyManager(biometric: biometric, storage: storage),
        ),
        biometricServiceProvider.overrideWithValue(biometric),
      ],
      child: const MaterialApp(home: CarbonLotteryDashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final failure in [404, 501, 0]) {
    testWidgets(
      'dashboard failure $failure renders no invented money/actions',
      (tester) async {
        final transport = _Transport(failure);
        await _mount(tester, transport);
        expect(transport.requests.length, 1);
        expect(find.text('12500 credits'), findsNothing);
        expect(find.text('250 credits'), findsNothing);
        expect(find.textContaining('Epoch '), findsNothing);
        expect(find.text('Deposit'), findsNothing);
        expect(find.text('Withdraw'), findsNothing);
      },
    );
    for (final action in CarbonLotteryAction.values) {
      testWidgets(
        '${action.name} failure $failure has no success/queued result',
        (tester) async {
          final transport = _Transport(failure, payload: dashboard);
          await _mount(tester, transport);
          final label = action == CarbonLotteryAction.deposit
              ? 'Deposit'
              : 'Withdraw';
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, label));
          await tester.pumpAndSettle();
          expect(transport.requests.where((r) => r.method == 'POST').length, 1);
          expect(find.textContaining('queued'), findsNothing);
          expect(find.textContaining('request sent'), findsNothing);
          expect(find.textContaining('local-'), findsNothing);
          expect(find.byType(SnackBar), findsOneWidget);
        },
      );
    }
  }
  testWidgets('no wallet asks for a wallet and sends no request', (
    tester,
  ) async {
    final transport = _Transport(404);
    await _mount(tester, transport, wallet: false);
    expect(find.textContaining('Create or import a wallet'), findsOneWidget);
    expect(find.textContaining('Epoch '), findsNothing);
    expect(transport.requests, isEmpty);
  });
  testWidgets('real server dashboard renders its values', (tester) async {
    await _mount(tester, _Transport(null, payload: dashboard));
    expect(find.text('Epoch 7'), findsOneWidget);
    expect(find.text('987 credits'), findsOneWidget);
    expect(find.text('Deposit'), findsOneWidget);
  });
  test('successful HTTP with no acknowledged request is a failure', () async {
    final result = await _repo(_Transport(null))
        .requestDeposit(walletAddress: 'synthetic-wallet', amountCredits: '25');
    expect(result.isLeft(), isTrue);
  });
  testWidgets('200 with missing fields never fabricates zero dashboard', (
    tester,
  ) async {
    await _mount(tester, _Transport(null, payload: <String, Object>{}));
    expect(find.textContaining('Epoch '), findsNothing);
    expect(find.text('0 credits'), findsNothing);
    expect(find.text('Deposit'), findsNothing);
  });
}
