import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/utils/wrf_units.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';
import 'package:wrfcoin_mobile/services/observability/app_logger.dart';

import '../../../../test_helpers/fakes.dart';

const _seedHex =
    '0x73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883';
const _recipient = '0x2222222222222222222222222222222222222222';

class _TestWalletNotifier extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => const WalletModel(
    address: '0x3f995ceb27e8177077dbed8b1e4f696af74da492',
    balance: '1000000000',
  );

  @override
  Future<void> refresh() async {}
}

class _TestTransactionsNotifier extends TransactionsNotifier {
  @override
  Future<TransactionsState> build() async =>
      const TransactionsState(items: [], hasMore: false, loadingMore: false);

  @override
  Future<void> refresh() async {}
}

Future<void> _pumpAndSend(
  WidgetTester tester,
  FakeWalletRepository repository, {
  required String amount,
  String to = _recipient,
  bool authenticate = true,
  MemoryLogSink? logs,
}) async {
  final signer = await Ed25519TransferSigner.fromSeedHex(_seedHex);
  final address = WalletSetupService().chainAddressFromEd25519(
    signer.publicKey,
  );
  final storage = InMemoryKeyValueStorage();
  await storage.write(key: 'wrf_address', value: address);
  await storage.write(key: 'wrf_private_key', value: _seedHex);
  await storage.write(
    key: 'wrf_key_scheme',
    value: KeyManager.canonicalKeyScheme,
  );
  final biometric = BiometricService(
    client: FakeLocalAuthClient(authenticateResult: authenticate),
  );
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/send', builder: (_, _) => const SendScreen()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (logs != null) logSinksProvider.overrideWithValue([logs]),
        walletRepositoryProvider.overrideWithValue(repository),
        walletSecureStorageProvider.overrideWithValue(
          FakeWalletSecureStorage(),
        ),
        biometricServiceProvider.overrideWithValue(biometric),
        keyManagerProvider.overrideWithValue(
          KeyManager(biometric: biometric, storage: storage),
        ),
        walletProvider.overrideWith(_TestWalletNotifier.new),
        transactionsProvider.overrideWith(_TestTransactionsNotifier.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Send to'), to);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Amount (WRF)'),
    amount,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
  await tester.pumpAndSettle();
  if (find.widgetWithText(TextButton, 'Send').evaluate().isNotEmpty) {
    final parsedAmount = wrfBaseUnitsToDisplay(wrfDisplayToBaseUnits(amount)!);
    expect(find.textContaining('Amount: $parsedAmount WRF'), findsOneWidget);
    expect(find.textContaining('credits'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final key in ['hash', 'tx_id']) {
    testWidgets('submission receipt shows returned $key without settlement', (
      tester,
    ) async {
      final id = List.filled(64, 'a').join();
      final repository = FakeWalletRepository(
        sendTransactionResult: Right({
          key: id,
          'status': 'submitted',
          'settled': false,
        }),
      );
      final logs = MemoryLogSink();
      await _pumpAndSend(tester, repository, amount: '1', logs: logs);
      expect(find.text('Submission receipt'), findsOneWidget);
      expect(find.text(id), findsOneWidget);
      expect(
        find.text('Submitted. Settlement has not been verified.'),
        findsOneWidget,
      );
      expect(find.text('Sent successfully'), findsNothing);
      expect(
        logs.entries.where((e) => e.event.startsWith('wallet_send')),
        isEmpty,
      );
      await tester.pump(const Duration(seconds: 30));
      expect(repository.sendCalls, 1);
      expect(find.text(id), findsOneWidget);
    });
  }

  testWidgets('missing identifier is explicit and does not imply settlement', (
    tester,
  ) async {
    final repository = FakeWalletRepository(
      sendTransactionResult: const Right({'status': 'submitted'}),
    );
    await _pumpAndSend(tester, repository, amount: '1');
    expect(find.text('Submission receipt'), findsOneWidget);
    expect(
      find.text(
        'Transaction identifier unavailable. Check wallet history before sending again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sent successfully'), findsNothing);
    expect(repository.sendCalls, 1);
  });

  for (final invalid in [
    123,
    '',
    'unknown',
    'raw response\nsecond line',
    List.filled(129, 'a').join(),
  ]) {
    testWidgets('malformed identifier stays unavailable ($invalid)', (
      tester,
    ) async {
      final repository = FakeWalletRepository(
        sendTransactionResult: Right({
          'hash': invalid,
          'status': 'submitted',
          'unrelated': 'response sentinel',
        }),
      );
      final logs = MemoryLogSink();
      await _pumpAndSend(tester, repository, amount: '1', logs: logs);
      expect(find.text('Submission receipt'), findsOneWidget);
      expect(
        find.text(
          'Transaction identifier unavailable. Check wallet history before sending again.',
        ),
        findsOneWidget,
      );
      expect(find.text('response sentinel'), findsNothing);
      expect(
        logs.entries.where((e) => e.event.startsWith('wallet_send')),
        isEmpty,
      );
      expect(repository.sendCalls, 1);
    });
  }

  testWidgets('timeout is not a receipt or an automatic resend', (
    tester,
  ) async {
    final repository = FakeWalletRepository(
      sendTransactionResult: const Left(NetworkFailure('Timeout')),
    );
    await _pumpAndSend(tester, repository, amount: '1');
    expect(find.text('Submission receipt'), findsNothing);
    expect(find.text('Sent successfully'), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(repository.sendCalls, 1);
  });

  testWidgets(
    'pending send stays on screen with an inline notice and no error toast',
    (tester) async {
      final repository = FakeWalletRepository(
        sendTransactionResult: const Left(
          ServerFailure('raw replay sentinel', statusCode: 409),
        ),
      );
      await _pumpAndSend(tester, repository, amount: '1.5');
      expect(
        find.text(
          'Previous transfer still pending; try again after it confirms',
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(SendScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(repository.sendCalls, 1);
      expect(repository.sentAmountBaseUnits, ['150000000']);
    },
  );
  testWidgets('sends the display amount as signed integer base units', (
    tester,
  ) async {
    final repository = FakeWalletRepository(
    );
    await _pumpAndSend(tester, repository, amount: '1.5');

    expect(repository.sendCalls, 1);
    expect(repository.sentAmountBaseUnits, ['150000000']);
    expect(repository.sentTo, [_recipient]);
  });

  testWidgets('Send accepts comma decimal and signs exact base units', (
    tester,
  ) async {
    final repository = FakeWalletRepository(
    );
    await _pumpAndSend(tester, repository, amount: '1,25');

    expect(find.text('Invalid amount'), findsNothing);
    expect(repository.sendCalls, 1);
    expect(repository.sentAmountBaseUnits, ['125000000']);
    expect(repository.sentTo, [_recipient]);
  });

  testWidgets('ambiguous comma amount explains refusal and sends nothing', (
    tester,
  ) async {
    final repository = FakeWalletRepository(
    );
    await _pumpAndSend(tester, repository, amount: '1,000');

    expect(
      find.text('Ambiguous amount: use a dot for decimals (e.g. 1.000)'),
      findsOneWidget,
    );
    expect(repository.sendCalls, 0);
    expect(repository.sentAmountBaseUnits, isEmpty);
    expect(find.text('Confirm Send'), findsNothing);
  });

  testWidgets('mixed separators are refused by the Send form', (tester) async {
    final repository = FakeWalletRepository(
    );
    await _pumpAndSend(tester, repository, amount: '1,250.5');

    expect(find.text('Invalid amount'), findsOneWidget);
    expect(repository.sendCalls, 0);
    expect(repository.sentAmountBaseUnits, isEmpty);
  });

  testWidgets('smallest unit converts exactly (no floating point)', (
    tester,
  ) async {
    final repository = FakeWalletRepository(
    );
    await _pumpAndSend(tester, repository, amount: '0.00000001');

    expect(repository.sentAmountBaseUnits, ['1']);
  });

  testWidgets('more than 8 decimals is rejected, never rounded or sent', (
    tester,
  ) async {
    final repository = FakeWalletRepository(
    );
    await _pumpAndSend(tester, repository, amount: '1.000000001');

    expect(find.text('Invalid amount'), findsOneWidget);
    expect(repository.sendCalls, 0);
  });

  testWidgets('non-hex recipient is rejected before signing', (tester) async {
    final repository = FakeWalletRepository(
    );
    await _pumpAndSend(
      tester,
      repository,
      amount: '1',
      to: 'wrf1234567890abcdef1234',
    );

    expect(find.text('Must be a 0x... address'), findsOneWidget);
    expect(repository.sendCalls, 0);
  });

  testWidgets('failed biometric unlock of the signing key sends nothing', (
    tester,
  ) async {
    final repository = FakeWalletRepository(
    );
    await _pumpAndSend(tester, repository, amount: '1', authenticate: false);

    expect(find.text('Authentication required to send'), findsOneWidget);
    expect(repository.sendCalls, 0);
  });
}
