import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/feature_flags/build_flags.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transfer_fee.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../../../test_helpers/fakes.dart';

const _from = '0x1111111111111111111111111111111111111111';
const _to = '0x2222222222222222222222222222222222222222';

class _Wallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async =>
      const WalletModel(address: _from, balance: '1000000000');
}

class _SequencedFees extends FakeWalletRepository {
  _SequencedFees(this.answers);
  final List<Either<Failure, TransferFeeQuote>> answers;
  @override
  Future<Either<Failure, TransferFeeQuote>> getTransferFee(
    String address,
  ) async {
    transferFeeReads++;
    return answers.length > 1 ? answers.removeAt(0) : answers.first;
  }
}

Future<void> _pump(
  WidgetTester tester,
  FakeWalletRepository repository, {
  ThemeData? theme,
}) async {
  final storage = InMemoryKeyValueStorage();
  await storage.write(key: 'wrf_address', value: _from);
  await storage.write(
    key: 'wrf_key_scheme',
    value: KeyManager.canonicalKeyScheme,
  );
  // Public synthetic seed used throughout the wallet widget fixtures.
  await storage.write(
    key: 'wrf_private_key',
    value: '0x73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        walletSendEnabledProvider.overrideWithValue(true),
        walletRepositoryProvider.overrideWithValue(repository),
        walletProvider.overrideWith(_Wallet.new),
        walletSecureStorageProvider.overrideWithValue(
          FakeWalletSecureStorage(),
        ),
        keyManagerProvider.overrideWithValue(
          KeyManager(
            biometric: BiometricService(client: FakeLocalAuthClient()),
            storage: storage,
          ),
        ),
      ],
      child: MaterialApp(theme: theme, home: const SendScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Send to'), _to);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Amount (WRF)'),
    '2',
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSend(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Send'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
  await tester.pumpAndSettle();
}

void main() {
  group('TransferFeeQuote.fromNonceResponse', () {
    Map<String, dynamic> fee(Object? value) => {
      'address': _from,
      'nonce': '3',
      'transfer_fee': value,
    };
    Map<String, dynamic> core4({
      bool active = true,
      bool scheduled = true,
      Object? baseUnits = '5000',
    }) => {
      'feature': 'transfer_fee_burn',
      'active': active,
      'scheduled': scheduled,
      'next_height': 12000,
      'base_units': baseUnits,
      'wrf': '0.00005',
      'burned': true,
      'sponsorable': false,
    };

    test('today\'s backend answer has no field: not reported', () {
      final quote = TransferFeeQuote.fromNonceResponse({
        'address': _from,
        'nonce': '3',
      });
      expect(quote.state, TransferFeeState.notReported);
      expect(quote.reserveBaseUnits, BigInt.zero);
      expect(quote.isStated, isFalse);
    });

    test('active fee is known and reserved in full', () {
      final quote = TransferFeeQuote.fromNonceResponse(fee(core4()));
      expect(quote.state, TransferFeeState.known);
      expect(quote.reserveBaseUnits, BigInt.from(5000));
      expect(quote.label, 'Network fee: 0.00005 WRF (burned)');
    });

    test('no fee on chain is a stated zero', () {
      final quote = TransferFeeQuote.fromNonceResponse(
        fee(core4(active: false, scheduled: false, baseUnits: '0')),
      );
      expect(quote.reserveBaseUnits, BigInt.zero);
      expect(quote.isStated, isTrue);
      expect(quote.label, 'Network fee: none');
    });

    test('a fee scheduled for later says so', () {
      final quote = TransferFeeQuote.fromNonceResponse(
        fee(core4(active: false, baseUnits: '0')),
      );
      expect(quote.reserveBaseUnits, BigInt.zero);
      expect(quote.label, 'Network fee: none yet (a fee is scheduled)');
    });

    final bad = <String, Object?>{
      'null': null,
      'not an object': '5000',
      'missing fields': <String, dynamic>{},
      'number amount': core4(baseUnits: 5000),
      'decimal amount': core4(baseUnits: '0.00005'),
      'negative amount': core4(baseUnits: '-1'),
      'leading zero': core4(baseUnits: '05000'),
      'active with zero': core4(baseUnits: '0'),
      'inactive with a figure': core4(active: false),
      'active as a string': {...core4(), 'active': 'true'},
      'scheduled missing': {...core4()}..remove('scheduled'),
    };
    bad.forEach((name, value) {
      test('$name is unknown and never zero', () {
        final quote = TransferFeeQuote.fromNonceResponse(fee(value));
        expect(quote.state, TransferFeeState.unknown);
        expect(quote.reserveBaseUnits, isNull);
        expect(quote.label, kNetworkFeeUnavailable);
      });
    });
  });

  group('Send with a known fee', () {
    testWidgets('shows it and keeps it back from the balance', (tester) async {
      final repo = FakeWalletRepository(
        transferFeeResult: Right(TransferFeeQuote.known(BigInt.from(5000))),
      );
      await _pump(tester, repo);
      expect(find.text('Network fee: 0.00005 WRF (burned)'), findsOneWidget);
      await _tapSend(tester);
      expect(find.text('Confirm Send'), findsOneWidget);
      expect(find.textContaining('Balance after: 7.99995 WRF'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await tester.pumpAndSettle();
      expect(repo.sendCalls, 1);
      expect(repo.sentAmountBaseUnits, ['200000000']);
    });

    testWidgets('amount plus fee over the balance is refused', (tester) async {
      final repo = FakeWalletRepository(
        transferFeeResult: Right(TransferFeeQuote.known(BigInt.from(5000))),
      );
      await _pump(tester, repo);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (WRF)'),
        '10',
      );
      await tester.pumpAndSettle();
      await _tapSend(tester);
      expect(find.text('Insufficient balance'), findsOneWidget);
      expect(find.text('Confirm Send'), findsNothing);
      expect(repo.sendCalls, 0);
    });
  });

  group('Send with an unknown fee', () {
    testWidgets('stops with a clear message and sends nothing', (tester) async {
      final repo = FakeWalletRepository(
        transferFeeResult: const Left(ServerFailure('read failed')),
      );
      await _pump(tester, repo);
      expect(find.text(kNetworkFeeUnavailable), findsOneWidget);
      await _tapSend(tester);
      expect(find.text('Confirm Send'), findsNothing);
      expect(find.text(kNetworkFeeUnavailable), findsNWidgets(2));
      expect(repo.sendCalls, 0);
    });

    testWidgets('a bad fee field also stops Send', (tester) async {
      final repo = FakeWalletRepository(
        transferFeeResult: Right(
          TransferFeeQuote.fromNonceResponse(const {'transfer_fee': null}),
        ),
      );
      await _pump(tester, repo);
      await _tapSend(tester);
      expect(find.text('Confirm Send'), findsNothing);
      expect(repo.sendCalls, 0);
    });

    testWidgets('Retry recovers once the fee can be read', (tester) async {
      final repo = _SequencedFees([
        const Left(ServerFailure('read failed')),
        const Right(TransferFeeQuote.notReported),
      ]);
      await _pump(tester, repo);
      expect(find.text(kNetworkFeeUnavailable), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry-network-fee')));
      await tester.pumpAndSettle();
      expect(
        find.text('Network fee: none reported by the network'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('retry-network-fee')), findsNothing);
    });

    testWidgets('pressing Send retries a failed read before refusing', (
      tester,
    ) async {
      final repo = _SequencedFees([
        const Left(ServerFailure('read failed')),
        const Right(TransferFeeQuote.notReported),
      ]);
      await _pump(tester, repo);
      await _tapSend(tester);
      expect(find.text('Confirm Send'), findsOneWidget);
    });

    testWidgets('losing the fee after the PIN gives a Cancel-only dialog', (
      tester,
    ) async {
      final repo = _SequencedFees([
        const Right(TransferFeeQuote.notReported),
        const Left(ServerFailure('read failed')),
      ]);
      await _pump(tester, repo);
      await _tapSend(tester);
      expect(find.text('Confirm Send'), findsOneWidget);
      expect(find.textContaining(kNetworkFeeUnavailable), findsWidgets);
      expect(find.widgetWithText(TextButton, 'Send'), findsNothing);
      expect(repo.sendCalls, 0);
    });
  });

  testWidgets('typing does not read the fee again', (tester) async {
    final repo = FakeWalletRepository();
    await _pump(tester, repo);
    final reads = repo.transferFeeReads;
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (WRF)'),
      '3',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(repo.transferFeeReads, reads);
  });

  group('screenshots', () {
    final out = Platform.environment['WRFCOIN_SCREENSHOT_DIR'];
    for (final (name, width, height) in [
      ('phone-390', 390.0, 844.0),
      ('desktop-1280', 1280.0, 800.0),
    ]) {
      for (final (state, result)
          in <(String, Either<Failure, TransferFeeQuote>)>[
            ('not-reported', const Right(TransferFeeQuote.notReported)),
            ('known-fee', Right(TransferFeeQuote.known(BigInt.from(5000)))),
            ('fee-unknown', const Left(ServerFailure('read failed'))),
          ]) {
        testWidgets('$state at $name', skip: out == null, (tester) async {
          await _loadRoboto();
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await _pump(
            tester,
            FakeWalletRepository(transferFeeResult: result),
            theme: AppTheme.lightTheme,
          );
          if (state != 'fee-unknown') await _tapSend(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('$out/send-$state-$name.png'),
          );
        });
      }
    }
  });
}

Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/home/tony/flutter';
  final loader = FontLoader('Roboto');
  for (final style in ['Regular', 'Medium', 'Bold']) {
    final bytes = File(
      '$root/bin/cache/artifacts/material_fonts/Roboto-$style.ttf',
    ).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}
