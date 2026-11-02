import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/pending_send.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/pending_send_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/pending_send_card.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../../../../test_helpers/fakes.dart';

const _seedHex =
    '0x73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883';
const _recipient = '0x2222222222222222222222222222222222222222';
final _start = DateTime.utc(2026, 11, 1, 12);
final _hash = List.filled(64, 'a').join();

class _Wallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => const WalletModel(
    address: '0x3f995ceb27e8177077dbed8b1e4f696af74da492',
    balance: '1000000000',
  );
  @override
  Future<void> refresh() async {}
}

class _Transactions extends TransactionsNotifier {
  @override
  Future<TransactionsState> build() async =>
      const TransactionsState(items: [], hasMore: false, loadingMore: false);
  @override
  Future<void> refresh() async {}
}

void main() {
  late FakeWalletRepository repository;
  late FakeWalletSecureStorage storage;
  late FakeLocalAuthClient auth;
  late String address;
  late DateTime now;

  setUp(() async {
    repository = FakeWalletRepository(
      sendTransactionResult: Right({'hash': _hash, 'status': 'submitted'}),
    );
    storage = FakeWalletSecureStorage();
    auth = FakeLocalAuthClient();
    now = _start;
    final signer = await Ed25519TransferSigner.fromSeedHex(_seedHex);
    address = WalletSetupService().chainAddressFromEd25519(signer.publicKey);
  });

  String saved({
    PendingSendPhase phase = PendingSendPhase.submitted,
    int? block,
  }) => PendingSend(
    from: address,
    to: _recipient,
    amountBaseUnits: '50000000',
    nonce: '7',
    submittedAt: _start,
    phase: phase,
    hash: _hash,
    blockHeight: block,
  ).encode();

  Future<void> pump(WidgetTester tester, Widget home) async {
    // Tall enough to hold the whole form: ListView builds only what's on screen.
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final keys = InMemoryKeyValueStorage();
    await keys.write(key: 'wrf_address', value: address);
    await keys.write(key: 'wrf_private_key', value: _seedHex);
    await keys.write(
      key: 'wrf_key_scheme',
      value: KeyManager.canonicalKeyScheme,
    );
    final biometric = BiometricService(client: auth);
    final router = GoRouter(
      initialLocation: '/screen',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: PendingSendCard()),
        ),
        GoRoute(path: '/screen', builder: (_, _) => home),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walletRepositoryProvider.overrideWithValue(repository),
          walletSecureStorageProvider.overrideWithValue(storage),
          biometricServiceProvider.overrideWithValue(biometric),
          keyManagerProvider.overrideWithValue(
            KeyManager(biometric: biometric, storage: keys),
          ),
          walletProvider.overrideWith(_Wallet.new),
          transactionsProvider.overrideWith(_Transactions.new),
          pendingSendClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool sendEnabled(WidgetTester tester) =>
      tester
          .widget<ElevatedButton>(find.byKey(const Key('send-submit')))
          .onPressed !=
      null;

  group('the Send screen', () {
    testWidgets('says so before anything is typed, and turns Send off', (
      tester,
    ) async {
      storage.pendingSend = saved();
      await pump(tester, const SendScreen());

      expect(find.text('Transaction pending'), findsOneWidget);
      expect(find.byKey(const Key('pending-send-blocks-send')), findsOneWidget);
      expect(find.textContaining('0.5 WRF to 0x222222'), findsOneWidget);
      expect(sendEnabled(tester), isFalse);
      // Top of the form, above the first field.
      expect(
        tester.getTopLeft(find.byKey(const Key('pending-send-card'))).dy,
        lessThan(
          tester.getTopLeft(find.widgetWithText(TextFormField, 'Send to')).dy,
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Send to'),
        _recipient,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (WRF)'),
        '1',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-submit')));
      await tester.pumpAndSettle();
      expect(
        auth.authenticateBiometricOnlyCalls,
        isEmpty,
        reason: 'never reaches the passcode',
      );
      expect(repository.sendCalls, 0);
    });

    testWidgets('turns Send back on when the chain confirms', (tester) async {
      storage.pendingSend = saved();
      await pump(tester, const SendScreen());
      expect(sendEnabled(tester), isFalse);

      repository
        ..accountNonceResult = const Right('8')
        ..includedBlockResult = const Right(4242);
      await tester.pump(pendingSendPollInterval);
      await tester.pumpAndSettle();

      expect(sendEnabled(tester), isTrue);
      expect(find.byKey(const Key('pending-send-blocks-send')), findsNothing);
    });

    testWidgets('checks as soon as it opens', (tester) async {
      storage.pendingSend = saved();
      repository
        ..accountNonceResult = const Right('8')
        ..includedBlockResult = const Right(4242);
      await pump(tester, const SendScreen());
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('an unreadable status says so and offers a manual check', (
      tester,
    ) async {
      storage.pendingSend = saved();
      repository.accountNonceResult = const Left(NetworkFailure());
      await pump(tester, const SendScreen());
      expect(
        find.byKey(const Key('pending-send-check-failed')),
        findsOneWidget,
      );
      expect(sendEnabled(tester), isFalse);

      repository
        ..accountNonceResult = const Right('8')
        ..includedBlockResult = const Right(4242);
      await tester.tap(find.byKey(const Key('pending-send-check-now')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pending-send-check-failed')), findsNothing);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('frees Send at the time limit even with reads failing', (
      tester,
    ) async {
      storage.pendingSend = saved();
      repository.accountNonceResult = const Left(NetworkFailure());
      await pump(tester, const SendScreen());
      expect(sendEnabled(tester), isFalse);

      now = _start.add(pendingSendTimeLimit);
      await tester.pump(pendingSendPollInterval);
      await tester.pumpAndSettle();

      expect(sendEnabled(tester), isTrue);
      expect(find.text('No confirmation yet'), findsOneWidget);
      expect(find.textContaining('before sending the same'), findsOneWidget);
    });

    Future<void> send(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Send to'),
        _recipient,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (WRF)'),
        '0.5',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await tester.pumpAndSettle();
    }

    testWidgets('a send appears as pending, and is saved', (tester) async {
      await pump(tester, const SendScreen());
      await send(tester);
      expect(find.text('Submission receipt'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Transaction pending'), findsOneWidget);
      expect(find.textContaining('0.5 WRF to 0x222222'), findsOneWidget);
      final stored = PendingSend.decode(storage.pendingSend)!;
      expect(stored.phase, PendingSendPhase.submitted);
      expect(stored.nonce, repository.signedNonce);
      expect(stored.hash, _hash);
      expect(stored.amountBaseUnits, '50000000');
      expect(stored.to, _recipient);
    });

    testWidgets('the 409 is still the backstop, and leaves no row', (
      tester,
    ) async {
      repository.sendTransactionResult = const Left(
        ServerFailure(pendingTransferMessage, statusCode: 409),
      );
      await pump(tester, const SendScreen());
      await send(tester);
      expect(find.text(pendingTransferMessage), findsOneWidget);
      expect(find.byKey(const Key('pending-send-card')), findsNothing);
      expect(storage.pendingSend, isNull);
    });

    testWidgets('a refused send leaves no row and Send on', (tester) async {
      repository.sendTransactionResult = const Left(
        ServerFailure('Rejected', statusCode: 400),
      );
      await pump(tester, const SendScreen());
      await send(tester);
      expect(find.byKey(const Key('pending-send-card')), findsNothing);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('a lost answer is followed, in plain words', (tester) async {
      repository.sendTransactionResult = const Left(NetworkFailure());
      await pump(tester, const SendScreen());
      await send(tester);
      expect(find.text('Send status unknown'), findsOneWidget);
      expect(sendEnabled(tester), isFalse);
    });
  });

  group('the row', () {
    Finder confirmed() => find.textContaining('confirmed', findRichText: true);

    testWidgets('only an included send ever says confirmed', (tester) async {
      for (final phase in [
        PendingSendPhase.submitted,
        PendingSendPhase.outcomeUnknown,
        PendingSendPhase.nonceUsedUnmatched,
      ]) {
        storage.pendingSend = saved(phase: phase);
        repository.accountNonceResult = phase == PendingSendPhase.submitted
            ? const Right('7')
            : const Right('8');
        await pump(tester, const Scaffold(body: PendingSendCard()));
        expect(find.byKey(const Key('pending-send-card')), findsOneWidget);
        expect(confirmed(), findsNothing, reason: phase.name);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('shows the outcome until dismissed', (tester) async {
      storage.pendingSend = saved(
        phase: PendingSendPhase.included,
        block: 4242,
      );
      await pump(tester, const Scaffold(body: PendingSendCard()));
      expect(find.text('Send confirmed'), findsOneWidget);
      expect(find.textContaining('block 4242'), findsOneWidget);
      expect(find.byKey(const Key('pending-send-check-now')), findsNothing);

      await tester.tap(find.byKey(const Key('pending-send-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pending-send-card')), findsNothing);
      expect(storage.pendingSend, isNull);
    });

    testWidgets('a waiting send cannot be dismissed', (tester) async {
      storage.pendingSend = saved();
      await pump(tester, const Scaffold(body: PendingSendCard()));
      expect(find.byKey(const Key('pending-send-dismiss')), findsNothing);
    });

    testWidgets('follows the send to its outcome on its own', (tester) async {
      storage.pendingSend = saved();
      await pump(tester, const Scaffold(body: PendingSendCard()));
      expect(find.text('Transaction pending'), findsOneWidget);

      await tester.pump(pendingSendPollInterval);
      await tester.pumpAndSettle();
      expect(find.text('Transaction pending'), findsOneWidget);

      repository
        ..accountNonceResult = const Right('8')
        ..includedBlockResult = const Right(4242);
      await tester.pump(pendingSendPollInterval);
      await tester.pumpAndSettle();
      expect(find.text('Send confirmed'), findsOneWidget);
    });

    testWidgets('stops reading the chain once settled', (tester) async {
      storage.pendingSend = saved();
      repository
        ..accountNonceResult = const Right('8')
        ..includedBlockResult = const Right(4242);
      await pump(tester, const Scaffold(body: PendingSendCard()));
      final reads = repository.accountNonceReads;
      await tester.pump(pendingSendPollInterval * 4);
      expect(repository.accountNonceReads, reads);
    });
  });
}
