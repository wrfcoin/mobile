// mobile#320: wallet creation must be usable on a real phone.
//
// 1. The recovery words stay visible until the user hides them or leaves.
// 2. The words can be copied, behind a confirmation, as a sensitive clip
//    that is cleared again after about 60 s if it is still ours.
// 3. "I've written it down" hides the words but keeps the 3-word
//    verification, and Complete Setup still stores the wallet.
//
// The mnemonic below is the public BIP-39 test vector, never a real wallet.
// Assertions compare it as a boolean so a failure never prints it.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/create_wallet_screen.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';
import 'package:wrfcoin_mobile/services/referral/referral_service.dart';
import 'package:wrfcoin_mobile/services/security/screen_security_service.dart';

import '../../../../test_helpers/fakes.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';
const _words = [
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'about',
];
const _clipboardChannel = MethodChannel(
  'com.wrfcoin.wrfcoin_mobile/secure_clipboard',
);

/// Deterministic generation: the test vector, verification words 1, 6, 12.
class _FixedWalletSetupService extends WalletSetupService {
  @override
  Future<WalletCredentials> generateWallet() => importFromMnemonic(_mnemonic);

  @override
  List<int> pickVerificationIndexes(int length, {required int count, random}) =>
      const [0, 5, 11];
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(dio: Dio());

  int signIns = 0;
  int ensures = 0;

  @override
  Future<bool> signInNow() async {
    signIns++;
    return true;
  }

  @override
  Future<bool> ensureWalletSession() async {
    ensures++;
    return true;
  }
}

class _FakeReferralService extends ReferralService {
  _FakeReferralService()
    : super(
        apiClient: ApiClient(
          dio: Dio(BaseOptions(baseUrl: 'http://localhost')),
        ),
      );

  @override
  Future<bool> trackReferralAttributionOnSignup({
    required String refereeAddress,
  }) async => true;
}

class _Harness {
  _Harness({FakeScreenSecurityClient? security})
    : screenSecurity = security ?? FakeScreenSecurityClient();

  final keyStorage = InMemoryKeyValueStorage();
  final walletStorage = FakeWalletSecureStorage();
  final FakeScreenSecurityClient screenSecurity;
  final api = _RecordingApiClient();

  /// Calls on the secure clipboard channel (method name, arguments).
  final clipboardCalls = <MethodCall>[];

  /// Calls to Flutter's own clipboard, which must never carry the phrase.
  final platformClipboardWrites = <Object?>[];

  Future<void> pump(WidgetTester tester) async {
    // storeKeys serialises on a per-isolate guard queue. Recreate it inside
    // this test's fake-async zone: a queue made in an earlier test's zone
    // never drains in this one.
    LoginAttemptGuard.resetIsolateStateForTest();
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_clipboardChannel, (call) async {
      clipboardCalls.add(call);
      return true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(_clipboardChannel, null),
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        platformClipboardWrites.add(call.arguments);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyManagerProvider.overrideWithValue(
            KeyManager(
              biometric: BiometricService(client: FakeLocalAuthClient()),
              storage: keyStorage,
            ),
          ),
          walletSetupServiceProvider.overrideWithValue(
            _FixedWalletSetupService(),
          ),
          walletSecureStorageProvider.overrideWithValue(walletStorage),
          referralServiceProvider.overrideWithValue(_FakeReferralService()),
          screenSecurityClientProvider.overrideWithValue(screenSecurity),
          apiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const CreateWalletScreen(),
              ),
              GoRoute(
                path: '/wallet',
                builder: (context, state) =>
                    const Scaffold(body: Text('Wallet home')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

Finder get _wordFields => find.byWidgetPredicate(
  (w) => w is TextField && (w.decoration?.labelText ?? '').startsWith('Word #'),
);

bool _phraseVisible(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .any((t) => t.data == _mnemonic || t.data?.contains('12. about') == true);

Future<void> _generate(WidgetTester tester) async {
  await tester.tap(find.text('Generate Wallet'));
  await tester.pump();
  await tester.pump();
}

Future<void> _verifyAndComplete(WidgetTester tester) async {
  expect(_wordFields, findsNWidgets(3));
  for (final field in tester.widgetList<TextField>(_wordFields).toList()) {
    final label = field.decoration!.labelText!;
    final index = int.parse(label.replaceFirst('Word #', '')) - 1;
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller == field.controller,
      ),
      _words[index],
    );
  }
  await tester.pump();
  await tester.tap(find.text('Complete Setup'));
  for (var i = 0; i < 50 && find.text('Wallet home').evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets(
    'recovery words wait for screen protection before the first frame',
    (tester) async {
      final security = _PendingScreenSecurity();
      final h = _Harness(security: security);
      await h.pump(tester);
      await _generate(tester);
      expect(security.enableCalls, 1);
      expect(_phraseVisible(tester), isFalse);
      expect(_wordFields, findsNothing);
      security.ready.complete();
      await tester.pump();
      expect(security.protectionEnabled, isTrue);
      expect(_phraseVisible(tester), isTrue);
      expect(_wordFields, findsNWidgets(3));
    },
  );

  testWidgets(
    'leaving while protection is pending never reveals words or leaves the flag enabled',
    (tester) async {
      final security = _PendingScreenSecurity();
      final h = _Harness(security: security);
      await h.pump(tester);
      await _generate(tester);
      await tester.pumpWidget(const SizedBox());
      security.ready.complete();
      await tester.pump();
      expect(_phraseVisible(tester), isFalse);
      expect(security.protectionEnabled, isFalse);
    },
  );

  group('mobile#320 item 1: the words do not auto-hide', () {
    testWidgets('the phrase is still readable after 5 minutes', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await _generate(tester);
      expect(_phraseVisible(tester), isTrue);

      await tester.pump(const Duration(minutes: 5));

      expect(_phraseVisible(tester), isTrue);
      expect(find.textContaining('Auto-clear'), findsNothing);
      expect(find.textContaining('Recovery phrase was cleared'), findsNothing);
      expect(_wordFields, findsNWidgets(3));
    });
  });

  group('mobile#320 item 3: hiding keeps the verification', () {
    testWidgets(
      '"I\'ve written it down" hides the words; verify and Complete Setup still work',
      (tester) async {
        final h = _Harness();
        await h.pump(tester);
        await _generate(tester);

        await tester.tap(find.text("I've written it down"));
        await tester.pump();

        expect(_phraseVisible(tester), isFalse);
        expect(
          find.text('Verify these words to confirm your backup:'),
          findsOneWidget,
        );
        expect(
          h.screenSecurity.protectionEnabled,
          isTrue,
          reason: 'FLAG_SECURE stays on until the wallet is saved',
        );

        // Well past the old 60 s timer: nothing is torn down.
        await tester.pump(const Duration(minutes: 3));
        await _verifyAndComplete(tester);

        expect(find.text('Wallet home'), findsOneWidget);
        expect(await h.keyStorage.read(key: 'wrf_address'), isNotNull);
        expect(
          await h.keyStorage.read(key: 'wrf_mnemonic') == _mnemonic,
          isTrue,
        );
        expect(h.walletStorage.backupConfirmed, isTrue);
      },
    );

    testWidgets('hidden words can be shown again', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await _generate(tester);

      await tester.tap(find.text("I've written it down"));
      await tester.pump();
      expect(_phraseVisible(tester), isFalse);

      await tester.tap(find.text('Show words'));
      await tester.pump();
      expect(_phraseVisible(tester), isTrue);
    });
  });

  group('mobile#320 item 2: copy the words', () {
    testWidgets('Copy asks first; cancelling copies nothing', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await _generate(tester);

      await tester.tap(find.byKey(const Key('create-wallet-copy')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(h.clipboardCalls, isEmpty);
      expect(h.platformClipboardWrites, isEmpty);
    });

    testWidgets(
      'confirmed copy is a sensitive clip, cleared after 60 s only if still ours',
      (tester) async {
        final h = _Harness();
        await h.pump(tester);
        await _generate(tester);

        await tester.tap(find.byKey(const Key('create-wallet-copy')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy anyway'));
        await tester.pump();

        expect(h.clipboardCalls, hasLength(1));
        final copy = h.clipboardCalls.single;
        expect(copy.method, 'copySensitive');
        final args = Map<String, Object?>.from(copy.arguments as Map);
        expect(args['text'] == _mnemonic, isTrue);
        final label = args['label'] as String;
        expect(label, isNotEmpty);
        expect(label.contains('abandon'), isFalse);
        expect(
          h.platformClipboardWrites,
          isEmpty,
          reason:
              'the phrase never goes through the unmarked Flutter clipboard',
        );

        await tester.pump(const Duration(seconds: 59));
        expect(h.clipboardCalls, hasLength(1));

        await tester.pump(const Duration(seconds: 2));
        expect(h.clipboardCalls, hasLength(2));
        expect(h.clipboardCalls.last.method, 'clearIfOurs');
        expect(
          Map<String, Object?>.from(h.clipboardCalls.last.arguments as Map),
          {'label': label},
        );
      },
    );

    testWidgets('leaving the screen clears a pending copy', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await _generate(tester);

      await tester.tap(find.byKey(const Key('create-wallet-copy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy anyway'));
      await tester.pump();
      expect(h.clipboardCalls, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(h.clipboardCalls.last.method, 'clearIfOurs');
    });
  });

  group('mobile#320 item 4: one explicit sign-in after creation', () {
    testWidgets('Complete Setup signs in exactly once', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await _generate(tester);
      await _verifyAndComplete(tester);

      expect(find.text('Wallet home'), findsOneWidget);
      expect(h.api.signIns, 1);
      expect(h.api.ensures, 0);
    });
  });
}

class _PendingScreenSecurity extends FakeScreenSecurityClient {
  final ready = Completer<void>();

  @override
  Future<void> enableProtection() async {
    enableCalls++;
    await ready.future;
    protectionEnabled = true;
  }
}
