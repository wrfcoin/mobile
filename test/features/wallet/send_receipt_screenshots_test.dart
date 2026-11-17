import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/core/theme/app_theme.dart';
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

import '../../test_helpers/fakes.dart';

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
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme.copyWith(
          textTheme: AppTheme.darkTheme.textTheme.apply(fontFamily: 'Roboto'),
        ),
        routerConfig: router,
      ),
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

// The send receipt with a tappable transaction reference. Renders with
// SCREENSHOT_FONTS set to Flutter's bin/cache/artifacts/material_fonts:
// flutter test --update-goldens test/features/wallet/send_receipt_screenshots_test.dart
void main() {
  final fonts = Platform.environment['SCREENSHOT_FONTS'];

  Future<void> load(String family, String file) async {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(
          ByteData.sublistView(File('$fonts/$file').readAsBytesSync()),
        ),
      );
    await loader.load();
  }

  const widths = {'phone-390': Size(390, 844), 'desktop-1440': Size(1440, 900)};
  for (final MapEntry(key: name, value: size) in widths.entries) {
    testWidgets('$name send receipt', (tester) async {
      await load('Roboto', 'Roboto-Regular.ttf');
      await load('MaterialIcons', 'MaterialIcons-Regular.otf');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = FakeWalletRepository(
        sendTransactionResult: Right({
          'hash': '0x${'3fa9' * 16}',
          'status': 'submitted',
          'settled': false,
        }),
      );
      await _pumpAndSend(tester, repository, amount: '1');
      expect(find.byKey(const Key('tx-reference-link')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../docs/screenshots/send-receipt/$name.png'),
      );
    }, skip: fonts == null);
  }
}
