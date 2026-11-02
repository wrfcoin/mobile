import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transfer_fee.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../../../test_helpers/fakes.dart';

const _address = '0x3f995ceb27e8177077dbed8b1e4f696af74da492';
const _to = '0x2222222222222222222222222222222222222222';

class _Wallet extends WalletNotifier {
  _Wallet(this.balance);
  final String? balance;
  @override
  Future<WalletModel?> build() async => balance == null
      ? null
      : WalletModel(address: _address, balance: balance!);
  void change(String? value) => state = AsyncData(
    value == null ? null : WalletModel(address: _address, balance: value),
  );
  void loading() => state = const AsyncLoading();
}

class _Fees extends FakeWalletRepository {
  _Fees(this.fee, this.stated);
  String? fee;

  /// False is today's backend: the answer has no fee field at all.
  final bool stated;
  @override
  Future<Either<Failure, TransferFeeQuote>> getTransferFee(
    String address,
  ) async {
    if (!stated) return const Right(TransferFeeQuote.notReported);
    return fee == null
        ? const Left(ServerFailure('fee read failed'))
        : Right(TransferFeeQuote.known(BigInt.parse(fee!)));
  }
}

class _Auth extends FakeLocalAuthClient {
  VoidCallback? afterPin;
  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    final result = await super.authenticate(
      reason: reason,
      biometricOnly: biometricOnly,
    );
    afterPin?.call();
    return result;
  }
}

Future<(_Wallet, _Auth, FakeWalletRepository)> _open(
  WidgetTester tester, {
  String? balance = '1000000000',
  String amount = '2',
  String? fee = '0',
  bool stated = true,
  bool changeDuringPin = false,
  String? balanceAfterPin,
  String? feeAfterPin,
  bool loseFeeDuringPin = false,
}) async {
  final storage = InMemoryKeyValueStorage();
  await storage.write(key: 'wrf_address', value: _address);
  await storage.write(
    key: 'wrf_key_scheme',
    value: KeyManager.canonicalKeyScheme,
  );
  // Public synthetic seed used throughout the wallet widget fixtures.
  await storage.write(
    key: 'wrf_private_key',
    value: '0x73457601ecc77e7b2f815efecba192aa0d1f9add743fdfbb9283cb5da3f20883',
  );
  final auth = _Auth();
  final biometric = BiometricService(client: auth);
  final wallet = _Wallet(balance);
  if (changeDuringPin) auth.afterPin = () => wallet.change(balanceAfterPin);
  final repo = _Fees(fee, stated);
  if (feeAfterPin != null) auth.afterPin = () => repo.fee = feeAfterPin;
  if (loseFeeDuringPin) auth.afterPin = () => repo.fee = null;
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
        walletRepositoryProvider.overrideWithValue(repo),
        walletProvider.overrideWith(() => wallet),
        walletSecureStorageProvider.overrideWithValue(
          FakeWalletSecureStorage(),
        ),
        keyManagerProvider.overrideWithValue(
          KeyManager(biometric: biometric, storage: storage),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await ProviderScope.containerOf(tester.element(find.byType(SendScreen)))
      .read(walletProvider.future);
  await tester.enterText(find.widgetWithText(TextFormField, 'Send to'), _to);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Amount (WRF)'),
    amount,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
  await tester.pumpAndSettle();
  return (wallet, auth, repo);
}

void main() {
  for (final amount in ['0.00000001', '2', '10']) {
    testWidgets('unknown fee blocks $amount before PIN without sending', (
      tester,
    ) async {
      final (_, auth, repo) = await _open(tester, amount: amount, fee: null);
      expect(find.text('Network fee unavailable — try again'), findsOneWidget);
      expect(auth.authenticateBiometricOnlyCalls, isEmpty);
      expect(find.text('Confirm Send'), findsNothing);
      expect(repo.sendCalls, 0);
    });
  }
  testWidgets('fee becoming unavailable during PIN gives Cancel only', (
    tester,
  ) async {
    final (_, auth, repo) = await _open(tester, loseFeeDuringPin: true);
    expect(auth.authenticateBiometricOnlyCalls, isNotEmpty);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Network fee unavailable — try again'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Balance after:'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Send'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(repo.sendCalls, 0);
  });
  testWidgets('retry with known fee allows amount plus fee equal to balance', (
    tester,
  ) async {
    final (_, auth, repo) = await _open(
      tester,
      balance: '300000000',
      fee: null,
    );
    expect(auth.authenticateBiometricOnlyCalls, isEmpty);
    expect(repo.sendCalls, 0);
    (repo as _Fees).fee = '100000000';
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (WRF)'),
      '2.0',
    );
    await tester.pumpAndSettle();
    // The Retry button makes the fee row taller, so scroll to the button.
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Balance after: 0 WRF'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 1);
  });
  testWidgets('final fee increasing after PIN blocks at confirmation', (
    tester,
  ) async {
    final (_, auth, repo) = await _open(
      tester,
      balance: '300000000',
      fee: '0',
      feeAfterPin: '200000000',
    );
    expect(auth.authenticateBiometricOnlyCalls, isNotEmpty);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Network fee: 2 WRF (burned)'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Insufficient balance: short by 1 WRF'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Send'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(repo.sendCalls, 0);
  });
  testWidgets('sponsored confirmation subtracts zero fee', (tester) async {
    final (_, _, repo) = await _open(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SendScreen));
    // Test the same confirmation widget without enabling the gated send path.
    final confirmed = showDialog<bool>(
      context: context,
      builder: (_) => SendConfirmationDialog(
        to: _to,
        amountBaseUnits: '200000000',
        sponsored: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Network fee: Free transfer'), findsOneWidget);
    expect(find.textContaining('Current balance: 10 WRF'), findsOneWidget);
    expect(find.textContaining('Balance after: 8 WRF'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Send'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pumpAndSettle();
    expect(await confirmed, isTrue);
    expect(repo.sendCalls, 0);
  });
  testWidgets('known fee exceeding balance blocks before PIN', (tester) async {
    final (_, auth, repo) = await _open(
      tester,
      balance: '250000000',
      fee: '100000000',
    );
    expect(find.text('Insufficient balance'), findsOneWidget);
    expect(auth.authenticateBiometricOnlyCalls, isEmpty);
    expect(repo.sendCalls, 0);
  });
  testWidgets('loading wallet blocks another send before PIN', (tester) async {
    final (wallet, auth, repo) = await _open(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    final calls = auth.authenticateBiometricOnlyCalls.length;
    wallet.loading();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();
    expect(
      find.text('Balance unavailable — refresh and try again'),
      findsOneWidget,
    );
    expect(auth.authenticateBiometricOnlyCalls, hasLength(calls));
    expect(repo.sendCalls, 0);
  });
  testWidgets(
    'confirmation shows exact amount, balance and authoritative fee',
    (tester) async {
      final (_, _, repo) = await _open(tester, fee: '100000000');
      expect(find.textContaining('To: $_to'), findsOneWidget);
      expect(find.textContaining('Amount: 2 WRF'), findsOneWidget);
      expect(find.textContaining('Current balance: 10 WRF'), findsOneWidget);
      expect(find.textContaining('Balance after: 7 WRF'), findsOneWidget);
      expect(repo.sendCalls, 0);
    },
  );
  testWidgets(
    'no fee figure from the network makes balance after approximate',
    (tester) async {
      final (_, _, repo) = await _open(tester, stated: false);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(
            'Network fee: none reported by the network',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Balance after: about 8 WRF'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Send'));
      await tester.pumpAndSettle();
      expect(repo.sendCalls, 1);
    },
  );
  testWidgets('comma amount is displayed parsed with a known zero fee', (
    tester,
  ) async {
    await _open(tester, amount: '1,25');
    expect(find.textContaining('Amount: 1.25 WRF'), findsOneWidget);
    expect(find.textContaining('Balance after: 8.75 WRF'), findsOneWidget);
  });
  testWidgets('insufficient balance blocks before PIN and sends nothing', (
    tester,
  ) async {
    final (_, auth, repo) = await _open(
      tester,
      balance: '100000000',
      fee: '100000000',
    );
    expect(find.text('Insufficient balance'), findsOneWidget);
    expect(auth.authenticateBiometricOnlyCalls, isEmpty);
    expect(find.text('Confirm Send'), findsNothing);
    expect(repo.sendCalls, 0);
  });
  for (final balance in <String?>[null, 'not-reported']) {
    testWidgets('unavailable balance $balance blocks before PIN', (
      tester,
    ) async {
      final (_, auth, repo) = await _open(tester, balance: balance);
      expect(
        find.text('Balance unavailable — refresh and try again'),
        findsOneWidget,
      );
      expect(auth.authenticateBiometricOnlyCalls, isEmpty);
      expect(repo.sendCalls, 0);
    });
  }
  testWidgets('balance falling during PIN gives Cancel-only confirmation', (
    tester,
  ) async {
    final (_, _, repo) = await _open(
      tester,
      fee: '100000000',
      changeDuringPin: true,
      balanceAfterPin: '100000000',
    );
    expect(find.text('Confirm Send'), findsOneWidget);
    expect(
      find.textContaining('Insufficient balance: short by 2 WRF'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Send'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(repo.sendCalls, 0);
  });
  testWidgets(
    'balance becoming unavailable during PIN omits after and blocks',
    (tester) async {
      final (_, _, repo) = await _open(tester, changeDuringPin: true);
      expect(
        find.textContaining('Current balance: unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('Balance after:'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Send'), findsNothing);
      expect(repo.sendCalls, 0);
    },
  );
  testWidgets('exact balance including fee allows send with zero after', (
    tester,
  ) async {
    final (_, _, repo) = await _open(
      tester,
      balance: '300000000',
      fee: '100000000',
    );
    expect(find.textContaining('Balance after: 0 WRF'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 1);
  });
  testWidgets('loading balance while confirmation is open removes Send', (
    tester,
  ) async {
    final (wallet, _, repo) = await _open(tester);
    wallet.loading();
    await tester.pumpAndSettle();
    expect(find.textContaining('Current balance: unavailable'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Send'), findsNothing);
    expect(repo.sendCalls, 0);
  });
}
