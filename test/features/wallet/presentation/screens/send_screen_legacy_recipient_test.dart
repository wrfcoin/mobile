import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';
import 'package:wrfcoin_mobile/services/crypto/signed_transfer.dart';

import '../../../../test_helpers/fakes.dart';

const _seedHex =
    '0x73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883';

// The incident pair (block 44378).
const _stevenCurrent = '0x1747c0169753965c854230c59c876be0f9b5a275';
const _stevenLegacy = '0x465230af3383c16d024c5f4b87ed2d1b595be148';
const _someoneElse = '0x2222222222222222222222222222222222222222';
const _ownLoginAlias = '0x3333333333333333333333333333333333333333';

/// Key manager whose biometric-gated key read can be paused by the test.
class _PausingKeyManager extends KeyManager {
  _PausingKeyManager({required super.biometric, required super.storage});

  final Completer<void> gate = Completer<void>();
  final Completer<void> reached = Completer<void>();

  @override
  Future<String?> getPrivateKey() async {
    if (!reached.isCompleted) reached.complete();
    await gate.future;
    return super.getPrivateKey();
  }
}

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

Future<FakeWalletRepository> _pump(
  WidgetTester tester, {
  List<AddressBookEntry> book = const [],
  String? loginAddress,
  KeyManager Function(BiometricService, KeyValueStorage)? keyManagerBuilder,
}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repository = FakeWalletRepository(
    sendTransactionResult: const Right({'status': 'submitted'}),
  );
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
  if (loginAddress != null) {
    await storage.write(key: 'wrf_login_address', value: loginAddress);
  }
  final biometric = BiometricService(
    client: FakeLocalAuthClient(authenticateResult: true),
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
        walletRepositoryProvider.overrideWithValue(repository),
        walletSecureStorageProvider.overrideWithValue(
          FakeWalletSecureStorage(addressBook: book),
        ),
        biometricServiceProvider.overrideWithValue(biometric),
        keyManagerProvider.overrideWithValue(
          keyManagerBuilder != null
              ? keyManagerBuilder(biometric, storage)
              : KeyManager(biometric: biometric, storage: storage),
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

Future<void> _fillAndSend(WidgetTester tester, {String? to}) async {
  if (to != null) {
    await tester.enterText(find.widgetWithText(TextFormField, 'Send to'), to);
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Amount (WRF)'),
    '1',
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  // Guard against a vacuous "blocked" result from an empty form.
  expect(
    tester
        .widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Amount (WRF)'),
        )
        .controller!
        .text,
    '1',
  );
  expect(
    tester
        .widget<TextFormField>(find.widgetWithText(TextFormField, 'Send to'))
        .controller!
        .text,
    isNotEmpty,
  );
  await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
  await tester.pumpAndSettle();
}

const _stevenLegacyEntry = AddressBookEntry(
  label: 'Steven',
  address: _stevenLegacy,
  status: AddressStatus.knownLegacy,
  replacementAddress: _stevenCurrent,
);

void main() {
  testWidgets('saved legacy contact is blocked with a reason, not sent', (
    tester,
  ) async {
    final repo = await _pump(tester, book: const [_stevenLegacyEntry]);
    await tester.tap(find.text(_stevenLegacy));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legacy-recipient-blocked')), findsOneWidget);
    expect(find.textContaining('receive-only'), findsWidgets);

    await _fillAndSend(tester);
    expect(find.text('Confirm Send'), findsNothing);
    expect(repo.sendCalls, 0);
  });

  testWidgets('typed legacy address of a marked contact is blocked too', (
    tester,
  ) async {
    final repo = await _pump(tester, book: const [_stevenLegacyEntry]);
    await _fillAndSend(
      tester,
      to: _stevenLegacy.toUpperCase().replaceFirst('0X', '0x'),
    );
    expect(find.text('Confirm Send'), findsNothing);
    expect(repo.sendCalls, 0);
  });

  testWidgets('verified replacement is offered and needs explicit selection', (
    tester,
  ) async {
    final repo = await _pump(tester, book: const [_stevenLegacyEntry]);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Send to'),
      _stevenLegacy,
    );
    await tester.pumpAndSettle();
    // Never auto-rewritten.
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Send to'))
          .controller!
          .text,
      _stevenLegacy,
    );
    final useReplacement = find.byKey(const Key('use-replacement-address'));
    expect(useReplacement, findsOneWidget);
    expect(find.textContaining(_stevenCurrent), findsWidgets);

    await tester.tap(useReplacement);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legacy-recipient-blocked')), findsNothing);

    await _fillAndSend(tester);
    expect(find.text('Confirm Send'), findsOneWidget);
    expect(find.textContaining('To: $_stevenCurrent'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 1);
  });

  testWidgets('own login alias is a known non-spendable destination', (
    tester,
  ) async {
    final repo = await _pump(tester, loginAddress: _ownLoginAlias);
    await _fillAndSend(tester, to: _ownLoginAlias);
    expect(find.byKey(const Key('legacy-recipient-blocked')), findsOneWidget);
    expect(find.text('Confirm Send'), findsNothing);
    expect(repo.sendCalls, 0);
  });

  testWidgets('unknown address is not blocked and not marked safe', (
    tester,
  ) async {
    final repo = await _pump(tester, book: const [_stevenLegacyEntry]);
    await _fillAndSend(tester, to: _someoneElse);
    expect(find.byKey(const Key('legacy-recipient-blocked')), findsNothing);
    expect(find.text('Confirm Send'), findsOneWidget);
    expect(find.textContaining('To: $_someoneElse'), findsOneWidget);
    expect(find.textContaining('not verified'), findsOneWidget);
    expect(find.textContaining('safe'), findsNothing);
    expect(find.textContaining('Verified recipient'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 1);
  });

  testWidgets('unverified saved contact confirms with label and full address', (
    tester,
  ) async {
    const book = [AddressBookEntry(label: 'Steven', address: _stevenCurrent)];
    await _pump(tester, book: book);
    await tester.tap(find.text(_stevenCurrent));
    await tester.pumpAndSettle();
    await _fillAndSend(tester);
    expect(find.textContaining('To: $_stevenCurrent'), findsOneWidget);
    expect(find.textContaining('Saved contact "Steven"'), findsOneWidget);
    expect(find.textContaining('not verified'), findsOneWidget);
  });

  testWidgets('same-name contacts are distinguishable by full address', (
    tester,
  ) async {
    const book = [
      AddressBookEntry(label: 'Steven', address: _stevenCurrent),
      _stevenLegacyEntry,
    ];
    await _pump(tester, book: book);
    expect(find.text(_stevenCurrent), findsOneWidget);
    expect(find.text(_stevenLegacy), findsOneWidget);
  });

  testWidgets(
    'review: changing destination during key access cannot bypass legacy block',
    (tester) async {
      late _PausingKeyManager keys;
      final repo = await _pump(
        tester,
        book: const [_stevenLegacyEntry],
        keyManagerBuilder: (biometric, storage) =>
            keys = _PausingKeyManager(biometric: biometric, storage: storage),
      );
      await _fillAndSend(tester, to: _someoneElse);
      await keys.reached.future;
      // The send attempt is paused inside the key read; the destination is
      // frozen, and even if it were changed the captured one is reassessed.
      final field = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Send to'),
      );
      field.controller!.text = _stevenLegacy;
      await tester.pump();
      keys.gate.complete();
      await tester.pumpAndSettle();
      if (find.text('Confirm Send').evaluate().isNotEmpty) {
        await tester.tap(find.widgetWithText(TextButton, 'Send'));
        await tester.pumpAndSettle();
      }
      // Nothing may ever be submitted to the legacy address; the only
      // permitted submission is to the destination captured at tap time.
      expect(
        repo.sentTo.map((a) => a.toLowerCase()),
        isNot(contains(_stevenLegacy)),
      );
    },
  );
}
