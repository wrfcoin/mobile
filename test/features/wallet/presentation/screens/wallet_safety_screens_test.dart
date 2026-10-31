import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/address_book_entry.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/address_book_transfer.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/send_allowlist.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_security_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/address_book_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/recovery_phrase_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_allowlist_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/security/screen_security_service.dart';

import '../../../../test_helpers/fakes.dart';

const _mom = '0x1111111111111111111111111111111111111111';
const _dad = '0x2222222222222222222222222222222222222222';
const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';

class _FakeGateway extends ContactsFileGateway {
  _FakeGateway([this.file]);
  final String? file;
  final shared = <String>[];

  @override
  Future<String?> pickFile() async => file;

  @override
  Future<void> share(String json) async => shared.add(json);
}

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 1, 12);
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required FakeWalletSecureStorage storage,
  _Clock? clock,
  KeyManager? keyManager,
  FakeScreenSecurityClient? screenSecurity,
  ContactsFileGateway? gateway,
}) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final c = clock ?? _Clock();
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('home')),
      GoRoute(path: '/start', builder: (_, _) => screen),
      GoRoute(
        path: '/wallet/contacts',
        builder: (_, _) => const Text('contacts'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        walletSecureStorageProvider.overrideWithValue(storage),
        allowlistClockProvider.overrideWithValue(() => c.now),
        if (keyManager != null)
          keyManagerProvider.overrideWithValue(keyManager),
        if (screenSecurity != null)
          screenSecurityServiceProvider.overrideWithValue(
            ScreenSecurityService(client: screenSecurity),
          ),
        if (gateway != null)
          contactsFileGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<KeyManager> _keyManager({
  String? mnemonic = _phrase,
  bool unlock = true,
}) async {
  final storage = InMemoryKeyValueStorage();
  await storage.write(key: 'wrf_address', value: _mom);
  if (mnemonic != null) {
    await storage.write(key: 'wrf_mnemonic', value: mnemonic);
  }
  return KeyManager(
    biometric: BiometricService(
      client: FakeLocalAuthClient(authenticateResult: unlock),
    ),
    storage: storage,
  );
}

void main() {
  group('send allowlist screen', () {
    testWidgets('turning on is instant and shows the exact help text', (
      tester,
    ) async {
      final storage = FakeWalletSecureStorage();
      await _pump(tester, const SendAllowlistScreen(), storage: storage);
      expect(find.text(sendAllowlistScopeNote), findsOneWidget);
      await tester.tap(find.byKey(const Key('allowlist-switch')));
      await tester.pumpAndSettle();
      expect(storage.sendAllowlist, const SendAllowlistSettings(enabled: true));
      expect(find.text('On. Send refuses everyone else.'), findsOneWidget);
    });

    testWidgets('turning off needs confirmation and waits 24 hours', (
      tester,
    ) async {
      final clock = _Clock();
      final storage = FakeWalletSecureStorage(
        sendAllowlist: const SendAllowlistSettings(enabled: true),
      );
      await _pump(
        tester,
        const SendAllowlistScreen(),
        storage: storage,
        clock: clock,
      );
      await tester.tap(find.byKey(const Key('allowlist-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Turn off the allowlist?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('allowlist-turn-off-confirm')));
      await tester.pumpAndSettle();

      expect(
        storage.sendAllowlist.turnsOffAt,
        clock.now.add(sendAllowlistCooldown),
      );
      expect(
        find.byKey(const Key('allowlist-turn-off-pending')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('allowlist-keep-on')));
      await tester.pumpAndSettle();
      expect(storage.sendAllowlist, const SendAllowlistSettings(enabled: true));
      expect(find.byKey(const Key('allowlist-turn-off-pending')), findsNothing);
    });

    testWidgets('dismissing the turn-off dialog keeps it on', (tester) async {
      final storage = FakeWalletSecureStorage(
        sendAllowlist: const SendAllowlistSettings(enabled: true),
      );
      await _pump(tester, const SendAllowlistScreen(), storage: storage);
      await tester.tap(find.byKey(const Key('allowlist-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it on'));
      await tester.pumpAndSettle();
      expect(storage.sendAllowlist.turnsOffAt, isNull);
    });

    testWidgets('allowing a contact while on is pending for 24 hours', (
      tester,
    ) async {
      final clock = _Clock();
      final storage = FakeWalletSecureStorage(
        addressBook: [const AddressBookEntry(label: 'Mom', address: _mom)],
        sendAllowlist: const SendAllowlistSettings(enabled: true),
      );
      await _pump(
        tester,
        const SendAllowlistScreen(),
        storage: storage,
        clock: clock,
      );
      await tester.tap(find.byKey(const Key('allow-$_mom')));
      await tester.pumpAndSettle();
      expect(find.text('Allow "Mom"?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('allowlist-allow-confirm')));
      await tester.pumpAndSettle();

      final saved = (await storage.getAddressBook()).single;
      expect(saved.allowedFrom, clock.now.add(sendAllowlistCooldown));
      expect(find.textContaining('Allowed from'), findsOneWidget);
    });

    testWidgets('allowing while off is instant', (tester) async {
      final clock = _Clock();
      final storage = FakeWalletSecureStorage(
        addressBook: [const AddressBookEntry(label: 'Mom', address: _mom)],
      );
      await _pump(
        tester,
        const SendAllowlistScreen(),
        storage: storage,
        clock: clock,
      );
      await tester.tap(find.byKey(const Key('allow-$_mom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('allowlist-allow-confirm')));
      await tester.pumpAndSettle();
      expect((await storage.getAddressBook()).single.allowedFrom, clock.now);
    });

    testWidgets('a due turn-off settles to off when the screen opens', (
      tester,
    ) async {
      final clock = _Clock();
      final storage = FakeWalletSecureStorage(
        sendAllowlist: SendAllowlistSettings(
          enabled: true,
          turnsOffAt: clock.now.subtract(const Duration(minutes: 1)),
        ),
      );
      await _pump(
        tester,
        const SendAllowlistScreen(),
        storage: storage,
        clock: clock,
      );
      expect(storage.sendAllowlist, SendAllowlistSettings.off);
      expect(find.text('Off. Send works with any address.'), findsOneWidget);
    });
  });

  group('recovery phrase screen', () {
    testWidgets('words stay hidden until the typed confirmation and unlock', (
      tester,
    ) async {
      final screen = FakeScreenSecurityClient();
      final storage = FakeWalletSecureStorage(backupConfirmed: false);
      await _pump(
        tester,
        const RecoveryPhraseScreen(),
        storage: storage,
        keyManager: await _keyManager(),
        screenSecurity: screen,
      );
      expect(
        find.text(
          'Anyone who sees these words can take everything in this wallet.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Nobody from WRFCoin'), findsOneWidget);
      final reveal = find.byKey(const Key('recovery-reveal'));
      expect(tester.widget<FilledButton>(reveal).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('recovery-confirm-field')),
        'show',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(reveal).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('recovery-confirm-field')),
        'Show my words',
      );
      await tester.pump();
      await tester.tap(reveal);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recovery-words')), findsOneWidget);
      expect(find.text('12. about'), findsOneWidget);
      expect(screen.protectionEnabled, isTrue);

      await tester.tap(find.byKey(const Key('recovery-done')));
      await tester.pumpAndSettle();
      expect(storage.backupConfirmed, isTrue);
      expect(screen.protectionEnabled, isFalse);
    });

    testWidgets('a failed unlock shows nothing', (tester) async {
      await _pump(
        tester,
        const RecoveryPhraseScreen(),
        storage: FakeWalletSecureStorage(),
        keyManager: await _keyManager(unlock: false),
        screenSecurity: FakeScreenSecurityClient(),
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirm-field')),
        revealPhraseConfirmation,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('recovery-reveal')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recovery-words')), findsNothing);
      expect(find.textContaining('was not unlocked'), findsOneWidget);
    });

    testWidgets('a private-key import says there is no phrase', (tester) async {
      await _pump(
        tester,
        const RecoveryPhraseScreen(),
        storage: FakeWalletSecureStorage(),
        keyManager: await _keyManager(mnemonic: 'imported private key 0x1111'),
        screenSecurity: FakeScreenSecurityClient(),
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirm-field')),
        revealPhraseConfirmation,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('recovery-reveal')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recovery-no-phrase')), findsOneWidget);
      expect(find.textContaining('imported private key'), findsNothing);
    });
  });

  group('contacts screen', () {
    testWidgets('add validates the address, then saves a named contact', (
      tester,
    ) async {
      final storage = FakeWalletSecureStorage();
      await _pump(
        tester,
        const AddressBookScreen(),
        storage: storage,
        keyManager: await _keyManager(),
      );
      await tester.tap(find.byKey(const Key('contacts-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('contact-name')), 'Mom');
      await tester.enterText(
        find.byKey(const Key('contact-address')),
        'wrf1nope',
      );
      await tester.tap(find.byKey(const Key('contact-save')));
      await tester.pumpAndSettle();
      expect(find.text('Must be a 0x... address'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('contact-address')), _mom);
      await tester.tap(find.byKey(const Key('contact-save')));
      await tester.pumpAndSettle();
      final saved = (await storage.getAddressBook()).single;
      expect(saved.label, 'Mom');
      expect(saved.allowedFrom, isNull);
      expect(find.text('Mom'), findsOneWidget);
    });

    testWidgets('rename keeps the address; remove deletes the contact', (
      tester,
    ) async {
      final storage = FakeWalletSecureStorage(
        addressBook: [const AddressBookEntry(label: 'Mom', address: _mom)],
      );
      await _pump(
        tester,
        const AddressBookScreen(),
        storage: storage,
        keyManager: await _keyManager(),
      );
      await tester.tap(find.text('Mom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('contact-name')), 'Mum');
      await tester.tap(find.byKey(const Key('contact-save')));
      await tester.pumpAndSettle();
      expect((await storage.getAddressBook()).single.label, 'Mum');

      await tester.tap(find.text('Mum'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contact-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contact-remove-confirm')));
      await tester.pumpAndSettle();
      expect(await storage.getAddressBook(), isEmpty);
    });

    testWidgets('import adds valid contacts, none allowed', (tester) async {
      final storage = FakeWalletSecureStorage(
        addressBook: [const AddressBookEntry(label: 'Mom', address: _mom)],
      );
      final file = jsonEncode({
        'format': addressBookFileFormat,
        'version': 1,
        'contacts': [
          {'name': 'Mom', 'address': _mom},
          {'name': 'Dad', 'address': _dad, 'allowed_from': 0},
          {'name': 'Bad', 'address': 'nope'},
        ],
      });
      await _pump(
        tester,
        const AddressBookScreen(),
        storage: storage,
        keyManager: await _keyManager(),
        gateway: _FakeGateway(file),
      );
      await tester.tap(find.byKey(const Key('contacts-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from file'));
      await tester.pumpAndSettle();
      final book = await storage.getAddressBook();
      expect(book.map((e) => e.label), ['Mom', 'Dad']);
      expect(book.every((e) => e.allowedFrom == null), isTrue);
      expect(find.textContaining('Added 1 contact'), findsOneWidget);
    });

    testWidgets('export shares names and addresses only', (tester) async {
      final gateway = _FakeGateway();
      await _pump(
        tester,
        const AddressBookScreen(),
        storage: FakeWalletSecureStorage(
          addressBook: [
            AddressBookEntry(
              label: 'Mom',
              address: _mom,
              allowedFrom: DateTime.utc(2026),
            ),
          ],
        ),
        keyManager: await _keyManager(),
        gateway: gateway,
      );
      await tester.tap(find.byKey(const Key('contacts-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export to file'));
      await tester.pumpAndSettle();
      final decoded = jsonDecode(gateway.shared.single) as Map;
      expect(decoded['contacts'], [
        {'name': 'Mom', 'address': _mom},
      ]);
    });
  });
}
