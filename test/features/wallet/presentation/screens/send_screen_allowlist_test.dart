import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/pending_send.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transfer_fee.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/send_allowlist.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/pending_send_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_security_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';

import '../../../../test_helpers/fakes.dart';

const _seedHex =
    '0x73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883';
const _mom = '0x1111111111111111111111111111111111111111';
const _stranger = '0x2222222222222222222222222222222222222222';
final _now = DateTime.utc(2026, 11, 1, 12);

class _WalletNotifier extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => const WalletModel(
    address: '0x3f995ceb27e8177077dbed8b1e4f696af74da492',
    balance: '1000000000',
  );

  @override
  Future<void> refresh() async {}
}

class _TxNotifier extends TransactionsNotifier {
  @override
  Future<TransactionsState> build() async =>
      const TransactionsState(items: [], hasMore: false, loadingMore: false);

  @override
  Future<void> refresh() async {}
}

/// Runs [onFeeRead] on each fee read. Send reads the fee again after the
/// device unlock, so this can change things just before the check that
/// precedes the confirmation dialog.
class _Repository extends FakeWalletRepository {
  _Repository() : super(sendTransactionResult: Right({'hash': _hash}));

  void Function()? onFeeRead;

  @override
  Future<Either<Failure, TransferFeeQuote>> getTransferFee(String address) {
    onFeeRead?.call();
    return super.getTransferFee(address);
  }
}

final _hash = List.filled(64, 'a').join();

late FakeWalletSecureStorage _storage;

Future<_Repository> _pump(
  WidgetTester tester, {
  required List<AddressBookEntry> book,
  required SendAllowlistSettings allowlist,
  bool pendingSend = false,
  DateTime? pendingClock,
}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repository = _Repository();
  final signer = await Ed25519TransferSigner.fromSeedHex(_seedHex);
  final address = WalletSetupService().chainAddressFromEd25519(
    signer.publicKey,
  );
  _storage = FakeWalletSecureStorage(
    addressBook: book,
    sendAllowlist: allowlist,
  );
  if (pendingSend) {
    _storage.pendingSend = PendingSend(
      from: address,
      to: _mom,
      amountBaseUnits: '50000000',
      nonce: '7',
      submittedAt: _now,
      phase: PendingSendPhase.submitted,
      hash: _hash,
    ).encode();
  }
  final storage = InMemoryKeyValueStorage();
  await storage.write(key: 'wrf_address', value: address);
  await storage.write(key: 'wrf_private_key', value: _seedHex);
  await storage.write(
    key: 'wrf_key_scheme',
    value: KeyManager.canonicalKeyScheme,
  );
  final biometric = BiometricService(
    client: FakeLocalAuthClient(authenticateResult: true),
  );
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/send', builder: (_, _) => const SendScreen()),
      GoRoute(
        path: '/wallet/allowlist',
        builder: (_, _) => const Text('allowlist screen'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        walletRepositoryProvider.overrideWithValue(repository),
        walletSecureStorageProvider.overrideWithValue(_storage),
        pendingSendClockProvider.overrideWithValue(() => pendingClock ?? _now),
        allowlistClockProvider.overrideWithValue(() => _now),
        biometricServiceProvider.overrideWithValue(biometric),
        keyManagerProvider.overrideWithValue(
          KeyManager(biometric: biometric, storage: storage),
        ),
        walletProvider.overrideWith(_WalletNotifier.new),
        transactionsProvider.overrideWith(_TxNotifier.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _fillAndSend(WidgetTester tester, String to) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Send to'), to);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Amount (WRF)'),
    '1',
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
  await tester.pumpAndSettle();
}

const _on = SendAllowlistSettings(enabled: true);

bool _sendEnabled(WidgetTester tester) =>
    tester
        .widget<ElevatedButton>(find.byKey(const Key('send-submit')))
        .onPressed !=
    null;

Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Send'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('allowlist on: an unsaved address is refused and not sent', (
    tester,
  ) async {
    final repo = await _pump(tester, book: const [], allowlist: _on);
    expect(find.text('Allowlist on: only allowed contacts'), findsOneWidget);
    await _fillAndSend(tester, _stranger);
    expect(
      find.byKey(const Key('allowlist-recipient-blocked')),
      findsOneWidget,
    );
    expect(find.text('Confirm Send'), findsNothing);
    expect(repo.sendCalls, 0);
  });

  testWidgets('allowlist on: a pending contact is refused with its time', (
    tester,
  ) async {
    final repo = await _pump(
      tester,
      book: [
        AddressBookEntry(
          label: 'Mom',
          address: _mom,
          allowedFrom: _now.add(const Duration(hours: 3)),
        ),
      ],
      allowlist: _on,
    );
    await _fillAndSend(tester, _mom);
    expect(find.text('Not allowed yet'), findsOneWidget);
    expect(find.textContaining('"Mom" can be used from'), findsWidgets);
    expect(find.text('Confirm Send'), findsNothing);
    expect(repo.sendCalls, 0);
  });

  testWidgets('allowlist on: an allowed contact reaches confirmation', (
    tester,
  ) async {
    await _pump(
      tester,
      book: [
        AddressBookEntry(
          label: 'Mom',
          address: _mom,
          allowedFrom: _now.subtract(const Duration(days: 1)),
        ),
      ],
      allowlist: _on,
    );
    await _fillAndSend(tester, _mom);
    expect(find.byKey(const Key('allowlist-recipient-blocked')), findsNothing);
    expect(find.text('Confirm Send'), findsOneWidget);
  });

  testWidgets('allowlist off: any address reaches confirmation', (
    tester,
  ) async {
    await _pump(tester, book: const [], allowlist: SendAllowlistSettings.off);
    await _fillAndSend(tester, _stranger);
    expect(find.byKey(const Key('allowlist-recipient-blocked')), findsNothing);
    expect(find.text('Confirm Send'), findsOneWidget);
  });

  testWidgets('a contact can be picked from the contacts sheet', (
    tester,
  ) async {
    await _pump(
      tester,
      book: const [AddressBookEntry(label: 'Mom', address: _mom)],
      allowlist: SendAllowlistSettings.off,
    );
    await tester.tap(find.byKey(const Key('send-pick-contact')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Mom').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Send to'))
          .controller!
          .text,
      _mom,
    );
  });

  group('a saved allowlist that cannot be read', () {
    const unreadable = SendAllowlistSettings.unreadableOn;
    final allowedMom = AddressBookEntry(
      label: 'Mom',
      address: _mom,
      allowedFrom: _now.subtract(const Duration(days: 2)),
    );

    testWidgets('refuses a stranger and says why, on screen and on Send', (
      tester,
    ) async {
      final repo = await _pump(tester, book: const [], allowlist: unreadable);
      await _fillAndSend(tester, _stranger);

      expect(
        find.descendant(
          of: find.byKey(const Key('allowlist-recipient-blocked')),
          matching: find.text("Can't read your send allowlist"),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('counts as on'), findsWidgets);
      expect(find.text('Open allowlist'), findsOneWidget);
      expect(find.text('Confirm Send'), findsNothing);
      expect(repo.sendCalls, 0);
    });

    testWidgets('an already allowed contact still reaches confirmation', (
      tester,
    ) async {
      await _pump(tester, book: [allowedMom], allowlist: unreadable);
      await _fillAndSend(tester, _mom);
      expect(find.text('Confirm Send'), findsOneWidget);
    });

    testWidgets('the first check stops it', (tester) async {
      final repo = await _pump(
        tester,
        book: const [],
        allowlist: SendAllowlistSettings.off,
      );
      _storage.sendAllowlist = unreadable;
      final feeReads = repo.transferFeeReads;
      await _fillAndSend(tester, _stranger);
      expect(find.text('Confirm Send'), findsNothing);
      expect(repo.sendCalls, 0);
      expect(repo.transferFeeReads, feeReads);
    });

    testWidgets('the check after the unlock and the fee read stops it', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        book: const [],
        allowlist: SendAllowlistSettings.off,
      );
      repo.onFeeRead = () => _storage.sendAllowlist = unreadable;
      await _fillAndSend(tester, _stranger);
      expect(repo.transferFeeReads, greaterThan(1));
      expect(find.text('Confirm Send'), findsNothing);
      expect(repo.sendCalls, 0);
    });

    testWidgets('the check after the confirmation dialog stops it', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        book: const [],
        allowlist: SendAllowlistSettings.off,
      );
      await _fillAndSend(tester, _stranger);
      expect(find.text('Confirm Send'), findsOneWidget);
      _storage.sendAllowlist = unreadable;
      await _tapConfirm(tester);
      expect(repo.sendCalls, 0);
      expect(_storage.pendingSend, isNull);
      expect(find.textContaining('counts as on'), findsWidgets);
    });

    testWidgets('contacts that fail to read stop it, with the reason', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        book: const [],
        allowlist: SendAllowlistSettings.off,
      );
      _storage.addressBookReadError = StateError('storage failed');
      await _fillAndSend(tester, _stranger);
      expect(find.text('Confirm Send'), findsNothing);
      expect(find.textContaining('counts as on'), findsOneWidget);
      expect(repo.sendCalls, 0);
    });
  });

  group('every check before submit reads fresh from storage', () {
    testWidgets('the first check: on in storage, off on screen', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        book: const [],
        allowlist: SendAllowlistSettings.off,
      );
      _storage.sendAllowlist = _on;
      final feeReads = repo.transferFeeReads;
      await _fillAndSend(tester, _stranger);
      expect(find.text('Confirm Send'), findsNothing);
      expect(repo.sendCalls, 0);
      // Stopped here, before the unlock: that is followed by a fee read.
      expect(repo.transferFeeReads, feeReads);
    });

    testWidgets('the check after the unlock and the fee read', (tester) async {
      final repo = await _pump(
        tester,
        book: const [],
        allowlist: SendAllowlistSettings.off,
      );
      repo.onFeeRead = () => _storage.sendAllowlist = _on;
      await _fillAndSend(tester, _stranger);
      expect(repo.transferFeeReads, greaterThan(1));
      expect(find.text('Confirm Send'), findsNothing);
      expect(repo.sendCalls, 0);
    });

    testWidgets('the check after the confirmation dialog', (tester) async {
      final repo = await _pump(
        tester,
        book: const [],
        allowlist: SendAllowlistSettings.off,
      );
      await _fillAndSend(tester, _stranger);
      expect(find.text('Confirm Send'), findsOneWidget);
      _storage.sendAllowlist = _on;
      await _tapConfirm(tester);
      expect(repo.sendCalls, 0);
      expect(_storage.pendingSend, isNull, reason: 'nothing was started');
    });
  });

  group('next to the pending-send block', () {
    testWidgets('both apply: the card and the notice, and Send stays off', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        book: const [],
        allowlist: _on,
        pendingSend: true,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Send to'),
        _stranger,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pending-send-blocks-send')), findsOneWidget);
      expect(
        find.byKey(const Key('allowlist-recipient-blocked')),
        findsOneWidget,
      );
      expect(_sendEnabled(tester), isFalse);
      expect(repo.sendCalls, 0);
    });

    testWidgets('once the pending block lifts, the allowlist still refuses', (
      tester,
    ) async {
      // Past the time limit the pending send no longer stops Send.
      final repo = await _pump(
        tester,
        book: const [],
        allowlist: _on,
        pendingSend: true,
        pendingClock: _now.add(pendingSendTimeLimit),
      );
      expect(_sendEnabled(tester), isTrue);
      await _fillAndSend(tester, _stranger);
      expect(find.text('Confirm Send'), findsNothing);
      expect(repo.sendCalls, 0);
    });

    testWidgets('an allowed contact is still stopped by a pending send', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        book: [
          AddressBookEntry(
            label: 'Mom',
            address: _mom,
            allowedFrom: _now.subtract(const Duration(days: 1)),
          ),
        ],
        allowlist: _on,
        pendingSend: true,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Send to'),
        _mom,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('allowlist-recipient-blocked')),
        findsNothing,
      );
      expect(_sendEnabled(tester), isFalse);
      expect(repo.sendCalls, 0);
    });
  });

  testWidgets('an allowed contact goes all the way and leaves a pending send', (
    tester,
  ) async {
    final repo = await _pump(
      tester,
      book: [
        AddressBookEntry(
          label: 'Mom',
          address: _mom,
          allowedFrom: _now.subtract(const Duration(days: 1)),
        ),
      ],
      allowlist: _on,
    );
    await _fillAndSend(tester, _mom);
    await _tapConfirm(tester);
    expect(repo.sendCalls, 1);
    expect(repo.sentTo, [_mom]);
    expect(PendingSend.decode(_storage.pendingSend)?.to, _mom);
  });
}
