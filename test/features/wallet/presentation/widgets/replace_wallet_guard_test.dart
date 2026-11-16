import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/replace_wallet_guard.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../../../test_helpers/fakes.dart';

const _address = '0xabcd567890abcdef1234567890abcdef12341234';

void main() {
  late InMemoryKeyValueStorage storage;
  late FakeLocalAuthClient auth;

  Future<void> seedWallet() async {
    await storage.write(key: 'wrf_address', value: _address);
    await storage.write(key: 'wrf_private_key', value: '0xold');
    await storage.write(key: 'wrf_mnemonic', value: 'old phrase');
  }

  Future<GoRouter> pump(WidgetTester tester, {bool unlock = true}) async {
    auth = FakeLocalAuthClient(authenticateResult: unlock);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/wallet',
          builder: (_, _) => const Scaffold(body: Text('WALLET TAB')),
        ),
        GoRoute(
          path: '/wallet/create',
          builder: (_, _) => const ReplaceWalletGuard(
            child: Scaffold(body: Text('CREATE FORM')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: auth),
              storage: storage,
            ),
          ),
          biometricServiceProvider.overrideWithValue(
            BiometricService(client: auth),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/wallet/create');
    await tester.pumpAndSettle();
    return router;
  }

  setUp(() => storage = InMemoryKeyValueStorage());

  test('the address is shortened to its start and end', () {
    expect(shortWalletAddress(_address), '0xabcd…1234');
    expect(shortWalletAddress('0xshort'), '0xshort');
  });

  testWidgets('a phone with a wallet sees the guard, not the form', (
    tester,
  ) async {
    await seedWallet();
    await pump(tester);
    expect(
      find.text('This phone already has a wallet (0xabcd…1234).'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Making or importing another one replaces it here. Without its '
        'recovery words or private key, the old wallet and its WRF are gone '
        'for good.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('I have my recovery words or key saved, replace it'),
      findsOneWidget,
    );
    expect(find.textContaining('12 recovery words'), findsNothing);
    expect(find.text('CREATE FORM'), findsNothing);
    expect(find.byKey(ReplaceWalletGuard.keepKey), findsOneWidget);
    expect(find.byKey(ReplaceWalletGuard.replaceKey), findsOneWidget);
  });

  testWidgets('Keep my wallet goes back and changes nothing', (tester) async {
    await seedWallet();
    await pump(tester);
    await tester.tap(find.byKey(ReplaceWalletGuard.keepKey));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('CREATE FORM'), findsNothing);
    expect(auth.authenticateBiometricOnlyCalls, isEmpty);
    expect(await storage.read(key: 'wrf_address'), _address);
    expect(await storage.read(key: 'wrf_private_key'), '0xold');
    expect(await storage.read(key: 'wrf_mnemonic'), 'old phrase');
  });

  testWidgets('Keep with nothing to go back to lands on the wallet tab', (
    tester,
  ) async {
    await seedWallet();
    final router = await pump(tester);
    router.go('/wallet/create');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ReplaceWalletGuard.keepKey));
    await tester.pumpAndSettle();
    expect(find.text('WALLET TAB'), findsOneWidget);
  });

  testWidgets('Replace without the device unlock keeps the guard', (
    tester,
  ) async {
    await seedWallet();
    await pump(tester, unlock: false);
    await tester.tap(find.byKey(ReplaceWalletGuard.replaceKey));
    await tester.pumpAndSettle();
    expect(auth.authenticateBiometricOnlyCalls, [false]);
    expect(find.text('CREATE FORM'), findsNothing);
    expect(
      find.text('The phone was not unlocked, so your wallet was not changed.'),
      findsOneWidget,
    );
    expect(await storage.read(key: 'wrf_address'), _address);
  });

  testWidgets('Replace after the device unlock opens the form', (tester) async {
    await seedWallet();
    await pump(tester);
    await tester.tap(find.byKey(ReplaceWalletGuard.replaceKey));
    await tester.pumpAndSettle();
    expect(auth.authenticateBiometricOnlyCalls, [false]);
    expect(find.text('CREATE FORM'), findsOneWidget);
    // Opening the form changes nothing yet; saving it is what replaces.
    expect(await storage.read(key: 'wrf_address'), _address);
  });

  testWidgets('a fresh phone goes straight to the form', (tester) async {
    await pump(tester);
    expect(find.text('CREATE FORM'), findsOneWidget);
    expect(find.textContaining('already has a wallet'), findsNothing);
    expect(auth.authenticateBiometricOnlyCalls, isEmpty);
  });

  testWidgets('an address without a private key is not a wallet to guard', (
    tester,
  ) async {
    await storage.write(key: 'wrf_address', value: _address);
    await pump(tester);
    expect(find.text('CREATE FORM'), findsOneWidget);
  });
}
