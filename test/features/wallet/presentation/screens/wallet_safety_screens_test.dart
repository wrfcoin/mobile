import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
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

class _ThrowingGateway extends ContactsFileGateway {
  const _ThrowingGateway(this.error);

  final Object error;

  @override
  Future<String?> pickFile() async => throw error;
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

    group('when the saved setting could not be read', () {
      testWidgets('shows on, says why, and turning off takes the 24 hours', (
        tester,
      ) async {
        final clock = _Clock();
        final storage = FakeWalletSecureStorage(
          sendAllowlist: SendAllowlistSettings.unreadableOn,
        );
        await _pump(
          tester,
          const SendAllowlistScreen(),
          storage: storage,
          clock: clock,
        );
        expect(find.byKey(const Key('allowlist-unreadable')), findsOneWidget);
        expect(find.textContaining('counts as on'), findsOneWidget);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );

        await tester.tap(find.byKey(const Key('allowlist-switch')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('allowlist-turn-off-confirm')));
        await tester.pumpAndSettle();

        expect(storage.sendAllowlist.unreadable, isFalse);
        expect(
          storage.sendAllowlist.turnsOffAt,
          clock.now.add(const Duration(hours: 24)),
        );
        expect(find.byKey(const Key('allowlist-unreadable')), findsNothing);
        expect(
          find.byKey(const Key('allowlist-turn-off-pending')),
          findsOneWidget,
        );
      });

      testWidgets('keep it on saves an ordinary on', (tester) async {
        final storage = FakeWalletSecureStorage(
          sendAllowlist: SendAllowlistSettings.unreadableOn,
        );
        await _pump(tester, const SendAllowlistScreen(), storage: storage);
        await tester.tap(find.byKey(const Key('allowlist-unreadable-keep-on')));
        await tester.pumpAndSettle();
        expect(
          storage.sendAllowlist,
          const SendAllowlistSettings(enabled: true),
        );
        expect(find.byKey(const Key('allowlist-unreadable')), findsNothing);
      });

      testWidgets('try again picks up a setting that reads now', (
        tester,
      ) async {
        final storage = FakeWalletSecureStorage(
          sendAllowlist: SendAllowlistSettings.unreadableOn,
        );
        await _pump(tester, const SendAllowlistScreen(), storage: storage);
        storage.sendAllowlist = SendAllowlistSettings.off;
        await tester.tap(find.byKey(const Key('allowlist-unreadable-retry')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('allowlist-unreadable')), findsNothing);
        expect(find.textContaining('Off.'), findsOneWidget);
      });

      testWidgets('a failed save stays on and says so', (tester) async {
        final storage = FakeWalletSecureStorage(
          sendAllowlist: SendAllowlistSettings.unreadableOn,
        );
        await _pump(tester, const SendAllowlistScreen(), storage: storage);
        storage.allowlistWriteError = StateError('storage failed');
        await tester.tap(find.byKey(const Key('allowlist-switch')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('allowlist-turn-off-confirm')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining("Couldn't save"), findsOneWidget);
        expect(find.byKey(const Key('allowlist-unreadable')), findsOneWidget);
        expect(storage.sendAllowlist, SendAllowlistSettings.unreadableOn);
      });
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

    Future<FakeScreenSecurityClient> showWords(WidgetTester tester) async {
      final screen = FakeScreenSecurityClient();
      await _pump(
        tester,
        const RecoveryPhraseScreen(),
        storage: FakeWalletSecureStorage(backupConfirmed: false),
        keyManager: await _keyManager(),
        screenSecurity: screen,
      );
      await tester.enterText(
        find.byKey(const Key('recovery-confirm-field')),
        revealPhraseConfirmation,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('recovery-reveal')));
      await tester.pumpAndSettle();
      expect(find.text('12. about'), findsOneWidget);
      return screen;
    }

    testWidgets('a moment away (inactive) hides the words, then shows them', (
      tester,
    ) async {
      final screen = await showWords(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('12. about'), findsNothing);
      expect(screen.protectionEnabled, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('12. about'), findsOneWidget);
    });

    // Real transitions: out through inactive and hidden, back the same way.
    for (final (name, out, back) in const [
      (
        'hidden',
        [AppLifecycleState.inactive, AppLifecycleState.hidden],
        [AppLifecycleState.inactive, AppLifecycleState.resumed],
      ),
      (
        'paused',
        [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ],
        [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ],
      ),
    ]) {
      testWidgets('leaving the app ($name) forgets the words: coming '
          'back needs the confirmation and a fresh unlock', (tester) async {
        final screen = await showWords(tester);
        for (final state in out) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pumpAndSettle();
        expect(find.text('12. about'), findsNothing);
        expect(screen.protectionEnabled, isFalse);
        for (final state in back) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pumpAndSettle();
        expect(find.text('12. about'), findsNothing);
        expect(find.byKey(const Key('recovery-words')), findsNothing);
        final reveal = find.byKey(const Key('recovery-reveal'));
        expect(tester.widget<FilledButton>(reveal).onPressed, isNull);
      });
    }

    testWidgets('leaving with the words showing turns the screen block off', (
      tester,
    ) async {
      final screen = await showWords(tester);
      expect(screen.protectionEnabled, isTrue);
      GoRouter.of(tester.element(find.byType(RecoveryPhraseScreen))).go('/');
      await tester.pumpAndSettle();
      expect(
        find.byType(RecoveryPhraseScreen, skipOffstage: false),
        findsNothing,
      );
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

    testWidgets(
      'at 390 px the address is one short line; a tap shows it whole',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const address = '0x1747c0169753965c854230c59c876be0f9b5a275';
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await _pump(
          tester,
          const AddressBookScreen(),
          storage: FakeWalletSecureStorage(
            addressBook: [
              const AddressBookEntry(label: 'Mom', address: address),
            ],
          ),
          keyManager: await _keyManager(),
        );

        final line = find.text('0x1747…a275');
        expect(line, findsOneWidget);
        expect(find.text(address), findsNothing);
        expect(tester.widget<Text>(line).maxLines, 1);
        final paragraph = tester.renderObject<RenderParagraph>(line);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'the short form fits on its line at 390 px',
        );

        await tester.tap(find.text('Mom'));
        await tester.pumpAndSettle();
        final field = tester.widget<TextFormField>(
          find.byKey(const Key('contact-address')),
        );
        expect(field.controller!.text, address);
        await tester.tap(find.byKey(const Key('contact-copy-address')));
        await tester.pumpAndSettle();
        expect(copied, address);
        expect(find.text('Address copied.'), findsOneWidget);
      },
    );

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
      expect(find.text('Add 1 contact?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('contacts-import-confirm')));
      await tester.pumpAndSettle();
      final book = await storage.getAddressBook();
      expect(book.map((e) => e.label), ['Mom', 'Dad']);
      expect(book.every((e) => e.allowedFrom == null), isTrue);
      expect(find.textContaining('Added 1 contact'), findsOneWidget);
    });

    group('importing shows what it will do first', () {
      const dadFile = {'name': 'Dad', 'address': _dad};
      String contactsFile(List<Map<String, Object?>> rows) => jsonEncode({
        'format': addressBookFileFormat,
        'version': 1,
        'contacts': rows,
      });

      Future<void> startImport(
        WidgetTester tester,
        FakeWalletSecureStorage storage,
        ContactsFileGateway gateway,
      ) async {
        await _pump(
          tester,
          const AddressBookScreen(),
          storage: storage,
          keyManager: await _keyManager(),
          gateway: gateway,
        );
        await tester.tap(find.byKey(const Key('contacts-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Import from file'));
        await tester.pumpAndSettle();
      }

      testWidgets('the name and full address, and nothing saved yet', (
        tester,
      ) async {
        final storage = FakeWalletSecureStorage();
        await startImport(
          tester,
          storage,
          _FakeGateway(contactsFile([dadFile])),
        );
        expect(
          find.byKey(const Key('contacts-import-preview')),
          findsOneWidget,
        );
        expect(find.text('Dad'), findsOneWidget);
        expect(find.text(_dad), findsOneWidget);
        expect(await storage.getAddressBook(), isEmpty);
      });

      testWidgets('Cancel saves nothing', (tester) async {
        final storage = FakeWalletSecureStorage();
        await startImport(
          tester,
          storage,
          _FakeGateway(contactsFile([dadFile])),
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(await storage.getAddressBook(), isEmpty);
      });

      testWidgets('a same-name address is flagged and Mom is untouched', (
        tester,
      ) async {
        final allowed = AddressBookEntry(
          label: 'Mom',
          address: _mom,
          allowedFrom: DateTime.utc(2026),
        );
        final storage = FakeWalletSecureStorage(addressBook: [allowed]);
        await startImport(
          tester,
          storage,
          _FakeGateway(
            contactsFile([
              {'name': 'mom', 'address': _dad},
            ]),
          ),
        );
        expect(
          find.byKey(const Key('contacts-import-name-clashes')),
          findsOneWidget,
        );
        expect(find.text(_dad), findsOneWidget);
        expect(find.byKey(const Key('contacts-import-confirm')), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        final book = await storage.getAddressBook();
        expect(book.single.address, _mom);
        expect(book.single.label, 'Mom');
        expect(book.single.allowedFrom, DateTime.utc(2026));
      });

      testWidgets('with the allowlist on, an import stays not allowed', (
        tester,
      ) async {
        final storage = FakeWalletSecureStorage(
          sendAllowlist: const SendAllowlistSettings(enabled: true),
        );
        await startImport(
          tester,
          storage,
          _FakeGateway(
            contactsFile([
              {...dadFile, 'allowed_from': 0},
            ]),
          ),
        );
        await tester.tap(find.byKey(const Key('contacts-import-confirm')));
        await tester.pumpAndSettle();
        final entry = (await storage.getAddressBook()).single;
        expect(entry.allowedFrom, isNull);
        expect(
          SendAllowlistPolicy()
              .check(to: _dad, book: [entry], settings: storage.sendAllowlist)
              .blocksSend,
          isTrue,
        );
      });

      for (final (name, message) in const [
        ('not a contacts file', 'This is not a WRFCoin contacts file.'),
        ('too large', 'This file is too large.'),
      ]) {
        testWidgets('a rejected file ($name) shows one plain message', (
          tester,
        ) async {
          final storage = FakeWalletSecureStorage();
          await startImport(
            tester,
            storage,
            _ThrowingGateway(ContactsFileRejected(message)),
          );
          expect(find.text(message), findsOneWidget);
          expect(
            find.byKey(const Key('contacts-import-preview')),
            findsNothing,
          );
          expect(await storage.getAddressBook(), isEmpty);
        });
      }

      testWidgets('malformed JSON shows the plain message', (tester) async {
        await startImport(
          tester,
          FakeWalletSecureStorage(),
          _FakeGateway('{"format": "wrfcoin-contacts", '),
        );
        expect(
          find.text('This is not a WRFCoin contacts file.'),
          findsOneWidget,
        );
      });

      testWidgets('anything else thrown shows no raw exception', (
        tester,
      ) async {
        await startImport(
          tester,
          FakeWalletSecureStorage(),
          _ThrowingGateway(StateError('secret detail')),
        );
        expect(find.text('That file could not be opened.'), findsOneWidget);
        expect(find.textContaining('secret detail'), findsNothing);
      });
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
