import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../test_helpers/fakes.dart';

class _FundedWallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => const WalletModel(
    address: '0x1111111111111111111111111111111111111111',
    balance: '1000000000',
  );
}

void main() {
  Future<void> pumpSendScreen(
    WidgetTester tester, {
    required BiometricService biometricService,
    bool legacyWallet = false,
  }) async {
    final keyStorage = InMemoryKeyValueStorage();
    await keyStorage.write(
      key: 'wrf_address',
      value: '0x1111111111111111111111111111111111111111',
    );
    if (!legacyWallet) {
      await keyStorage.write(
        key: 'wrf_key_scheme',
        value: KeyManager.canonicalKeyScheme,
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walletRepositoryProvider.overrideWithValue(
            FakeWalletRepository(
              estimateGasResult: const Right({
                'feeBaseUnits': '0',
                'authoritative': true,
              }),
            ),
          ),
          walletProvider.overrideWith(_FundedWallet.new),
          walletSecureStorageProvider.overrideWithValue(
            FakeWalletSecureStorage(),
          ),
          biometricServiceProvider.overrideWithValue(biometricService),
          keyManagerProvider.overrideWithValue(
            KeyManager(biometric: biometricService, storage: keyStorage),
          ),
        ],
        child: const MaterialApp(home: SendScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('validates required send form fields', (tester) async {
    await pumpSendScreen(
      tester,
      biometricService: BiometricService(client: FakeLocalAuthClient()),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pump();

    expect(find.text('Address required'), findsOneWidget);
    expect(find.text('Amount required'), findsOneWidget);
  });

  testWidgets('blocks send when biometric authentication fails', (
    tester,
  ) async {
    await pumpSendScreen(
      tester,
      biometricService: BiometricService(
        client: FakeLocalAuthClient(authenticateResult: false),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Send to'),
      '0x2222222222222222222222222222222222222222',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (WRF)'),
      '5',
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pump();

    expect(find.text('Authentication required to send'), findsOneWidget);
  });

  testWidgets('presents an unmarked legacy wallet as receive-only', (
    tester,
  ) async {
    await pumpSendScreen(
      tester,
      biometricService: BiometricService(client: FakeLocalAuthClient()),
      legacyWallet: true,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Send to'),
      '0x2222222222222222222222222222222222222222',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (WRF)'),
      '5',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pump();

    expect(
      find.textContaining('legacy wallet is receive-only'),
      findsOneWidget,
    );
  });
}
