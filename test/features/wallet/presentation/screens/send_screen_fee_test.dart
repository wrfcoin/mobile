import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../../../test_helpers/fakes.dart';

Future<void> _pumpFeeEstimate(
  WidgetTester tester,
  FakeWalletRepository repository, {
  String amount = '250',
}) async {
  final storage = InMemoryKeyValueStorage();
  await storage.write(
    key: 'wrf_address',
    value: '0x1111111111111111111111111111111111111111',
  );
  final biometric = BiometricService(client: FakeLocalAuthClient());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        walletRepositoryProvider.overrideWithValue(repository),
        walletSecureStorageProvider.overrideWithValue(
          FakeWalletSecureStorage(),
        ),
        keyManagerProvider.overrideWithValue(
          KeyManager(biometric: biometric, storage: storage),
        ),
      ],
      child: const MaterialApp(home: SendScreen()),
    ),
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Send to'),
    '0x2222222222222222222222222222222222222222',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Amount (WRF)'),
    amount,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

/// Response shape of backend #1200 for amountBaseUnits 25000000000 (250 WRF).
Map<String, dynamic> _backendEstimate({
  String amountBaseUnits = '25000000000',
  Object? feeBaseUnits = '25000000',
  bool authoritative = false,
}) => <String, dynamic>{
  'success': true,
  'amountBaseUnits': amountBaseUnits,
  'feeBaseUnits': ?feeBaseUnits,
  'unit': 'integer base units',
  'currency': 'WRF',
  'authoritative': authoritative,
  'source': 'backend-display-rule',
  'rule': 'floor(amountBaseUnits/1000)',
  'note': 'core4 charges no transfer fee; this figure is not debited on chain',
};

const _nonAuthoritativeLabel =
    'Fee estimate: 0.25 WRF (non-authoritative, not charged on chain)';

void main() {
  testWidgets('sends the display amount as integer base units', (tester) async {
    final repository = FakeWalletRepository(
      estimateGasResult: Right(_backendEstimate()),
    );
    await _pumpFeeEstimate(tester, repository);

    expect(repository.estimateGasAmounts, ['25000000000']);
  });

  testWidgets('fractional display amount converts exactly', (tester) async {
    final repository = FakeWalletRepository(
      estimateGasResult: Right(
        _backendEstimate(amountBaseUnits: '29000000', feeBaseUnits: '29000'),
      ),
    );
    await _pumpFeeEstimate(tester, repository, amount: '0.29');

    expect(repository.estimateGasAmounts, ['29000000']);
    expect(
      find.text(
        'Fee estimate: 0.00029 WRF (non-authoritative, not charged on chain)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('comma amount fee preview uses exact base units', (tester) async {
    final repository = FakeWalletRepository(
      estimateGasResult: Right(
        _backendEstimate(amountBaseUnits: '125000000', feeBaseUnits: '125000'),
      ),
    );
    await _pumpFeeEstimate(tester, repository, amount: '1,25');

    expect(repository.estimateGasAmounts, ['125000000']);
    expect(
      find.text(
        'Fee estimate: 0.00125 WRF (non-authoritative, not charged on chain)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('ambiguous comma amount never requests a fee estimate', (
    tester,
  ) async {
    final repository = FakeWalletRepository(
      estimateGasResult: Right(_backendEstimate()),
    );
    await _pumpFeeEstimate(tester, repository, amount: '1,000');

    expect(repository.estimateGasAmounts, isEmpty);
    expect(find.text(kFeeEstimateUnavailable), findsOneWidget);
  });

  testWidgets('amount with more than 8 decimals is never sent', (tester) async {
    final repository = FakeWalletRepository(
      estimateGasResult: Right(_backendEstimate()),
    );
    await _pumpFeeEstimate(tester, repository, amount: '1.000000001');

    expect(repository.estimateGasAmounts, isEmpty);
    expect(find.text(kFeeEstimateUnavailable), findsOneWidget);
  });

  testWidgets('estimate failure shows no invented fee', (tester) async {
    await _pumpFeeEstimate(
      tester,
      FakeWalletRepository(
        estimateGasResult: const Left(ServerFailure('unavailable')),
      ),
    );

    expect(find.text(kFeeEstimateUnavailable), findsOneWidget);
    expect(find.textContaining('0.001'), findsNothing);
  });

  testWidgets('feeBaseUnits renders as WRF labelled non-authoritative', (
    tester,
  ) async {
    await _pumpFeeEstimate(
      tester,
      FakeWalletRepository(estimateGasResult: Right(_backendEstimate())),
    );

    expect(find.text(_nonAuthoritativeLabel), findsOneWidget);
    expect(find.textContaining('Network fee:'), findsNothing);
  });

  testWidgets('authoritative response may be labelled as a network fee', (
    tester,
  ) async {
    await _pumpFeeEstimate(
      tester,
      FakeWalletRepository(
        estimateGasResult: Right(_backendEstimate(authoritative: true)),
      ),
    );

    expect(find.text('Network fee: 0.25 WRF'), findsOneWidget);
  });

  testWidgets('response without feeBaseUnits remains unavailable', (
    tester,
  ) async {
    await _pumpFeeEstimate(
      tester,
      FakeWalletRepository(
        estimateGasResult: Right(_backendEstimate(feeBaseUnits: null)),
      ),
    );

    expect(find.text(kFeeEstimateUnavailable), findsOneWidget);
  });

  testWidgets('legacy WRF-formatted fee field is not displayed', (
    tester,
  ) async {
    await _pumpFeeEstimate(
      tester,
      FakeWalletRepository(
        estimateGasResult: const Right({'fee': '0.25', 'authoritative': false}),
      ),
    );

    expect(find.text(kFeeEstimateUnavailable), findsOneWidget);
    expect(find.textContaining('0.25'), findsNothing);
  });

  group('feeWrfFromEstimate', () {
    test('formats feeBaseUnits with exact integer math', () {
      expect(
        feeWrfFromEstimate(
          _backendEstimate(),
          requestedBaseUnits: '25000000000',
        ),
        '0.25',
      );
      expect(
        feeWrfFromEstimate(
          _backendEstimate(amountBaseUnits: '1999', feeBaseUnits: '1'),
          requestedBaseUnits: '1999',
        ),
        '0.00000001',
      );
    });

    test('rejects non-integer, numeric, or mismatched responses', () {
      for (final bad in <Map<String, dynamic>>[
        _backendEstimate(feeBaseUnits: '0.25'),
        _backendEstimate(feeBaseUnits: 25000000),
        _backendEstimate(feeBaseUnits: '-1'),
        _backendEstimate(amountBaseUnits: '250'),
      ]) {
        expect(
          feeWrfFromEstimate(bad, requestedBaseUnits: '25000000000'),
          isNull,
          reason: '$bad',
        );
      }
    });
  });

  test('send screen contains no hard-coded 0.001 fee literal', () {
    final source = File(
      'lib/features/wallet/presentation/screens/send_screen.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('0.001')));
  });
}
