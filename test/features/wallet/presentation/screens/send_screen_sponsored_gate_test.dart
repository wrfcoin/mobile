import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/transactions_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../../../test_helpers/fakes.dart';

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

void main() {
  testWidgets('social wallet sees the normal fee label, not Free transfer', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walletRepositoryProvider.overrideWithValue(FakeWalletRepository()),
          walletSecureStorageProvider.overrideWithValue(
            FakeWalletSecureStorage(isSocial: true),
          ),
        ],
        child: const MaterialApp(home: SendScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Free transfer'), findsNothing);
    // No wallet is readable here, so no fee is claimed.
    expect(find.textContaining('none'), findsNothing);
  });

  testWidgets('social canonical wallet uses the ordinary send path', (
    tester,
  ) async {
    final repository = FakeWalletRepository();
    final keyStorage = InMemoryKeyValueStorage();
    await keyStorage.write(
      key: 'wrf_address',
      value: '0x3f995ceb27e8177077dbed8b1e4f696af74da492',
    );
    await keyStorage.write(key: 'wrf_key_scheme', value: 'ed25519-slip10');
    // Sending signs with the wallet's ed25519 seed (mobile#286).
    await keyStorage.write(
      key: 'wrf_private_key',
      value:
          '0x73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883',
    );
    final biometric = BiometricService(client: FakeLocalAuthClient());
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
            FakeWalletSecureStorage(isSocial: true),
          ),
          biometricServiceProvider.overrideWithValue(biometric),
          keyManagerProvider.overrideWithValue(
            KeyManager(biometric: biometric, storage: keyStorage),
          ),
          walletProvider.overrideWith(_TestWalletNotifier.new),
          transactionsProvider.overrideWith(_TestTransactionsNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Send to'),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (WRF)'),
      '5',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Free transfer'), findsNothing);
    expect(
      find.textContaining('Network fee: none reported by the network'),
      findsWidgets,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pumpAndSettle();

    expect(repository.sponsorGasCalls, 0);
    expect(repository.submitUserOpCalls, 0);
    expect(repository.sendCalls, 1);
  });

  test('userOp map has no client-generated hash or nonce key', () {
    final userOp = buildSponsoredUserOperation(
      from: 'wrf1sender',
      to: 'wrf1recipient',
      amount: '5',
      memo: 'test',
    );

    expect(userOp, isNot(contains('hash')));
    expect(userOp, isNot(contains('nonce')));
    expect(userOp['callData'], '0x');
  });
}
