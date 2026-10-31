import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/send_allowlist.dart';
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

Future<FakeWalletRepository> _pump(
  WidgetTester tester, {
  required List<AddressBookEntry> book,
  required SendAllowlistSettings allowlist,
}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repository = FakeWalletRepository(
    estimateGasResult: const Right({
      'feeBaseUnits': '0',
      'authoritative': true,
    }),
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
        walletSecureStorageProvider.overrideWithValue(
          FakeWalletSecureStorage(addressBook: book, sendAllowlist: allowlist),
        ),
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
}
