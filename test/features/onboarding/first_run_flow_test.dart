// A clean install through the real router, to the Collect screen. The phrase is
// the public BIP-39 test vector, never a real wallet.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/passkey_wallet_provider.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_setup_service.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';
import 'package:wrfcoin_mobile/services/referral/referral_service.dart';
import 'package:wrfcoin_mobile/services/security/screen_security_service.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/fakes.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';

(double, double) _ordered(double a, double b) => a > b ? (a, b) : (b, a);

class _FixedSetup extends WalletSetupService {
  @override
  Future<WalletCredentials> generateWallet() => importFromMnemonic(_mnemonic);

  @override
  List<int> pickVerificationIndexes(int length, {required int count, random}) =>
      const [0, 5, 11];
}

class _NoLoginApi extends ApiClient {
  _NoLoginApi() : super(dio: Dio());

  @override
  Future<bool> signInNow() async => true;

  @override
  Future<bool> ensureWalletSession() async => true;
}

class _NoReferrals extends ReferralService {
  _NoReferrals()
    : super(
        apiClient: ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://x'))),
      );

  @override
  Future<bool> trackReferralAttributionOnSignup({
    required String refereeAddress,
  }) async => true;
}

class _RecordingBrowser extends PasskeyBrowser {
  int opened = 0;

  @override
  Future<bool> open() async {
    opened++;
    return true;
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
  });
  tearDown(() => db.close());

  Future<void> frames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  String location(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>).first),
    );
    return container
        .read(appRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
  }

  Future<_RecordingBrowser> launch(
    WidgetTester tester, {
    bool withWallet = false,
  }) async {
    // storeKeys serialises on a per-isolate queue: remake it in this test's zone.
    LoginAttemptGuard.resetIsolateStateForTest();
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final browser = _RecordingBrowser();
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
        withWallet: withWallet,
        extraOverrides: [
          walletSetupServiceProvider.overrideWithValue(_FixedSetup()),
          apiClientProvider.overrideWithValue(_NoLoginApi()),
          referralServiceProvider.overrideWithValue(_NoReferrals()),
          screenSecurityServiceProvider.overrideWithValue(
            ScreenSecurityService(client: FakeScreenSecurityClient()),
          ),
          passkeyBrowserProvider.overrideWithValue(browser),
        ],
      ),
    );
    await frames(tester);
    return browser;
  }

  Future<void> toWalletChoice(WidgetTester tester) async {
    expect(find.byType(WelcomeScreen), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await frames(tester, 6);
    }
  }

  testWidgets('clean install: 12-word wallet, through to Collect', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await launch(tester);
    await toWalletChoice(tester);

    await tester.tap(find.byKey(const Key('welcome-create-wallet')));
    await frames(tester);
    expect(location(tester), '/wallet/create');

    await tester.tap(find.text('Generate Wallet'));
    await frames(tester);
    // The app follows the system theme, so this is what a light-mode phone gets.
    final word = find.text('1. abandon');
    final box = tester.widget<Container>(
      find.ancestor(of: word, matching: find.byType(Container)).first,
    );
    final background = (box.decoration! as BoxDecoration).color!;
    final ink = tester.renderObject<RenderParagraph>(word).text.style!.color!;
    final (hi, lo) = _ordered(
      ink.computeLuminance(),
      background.computeLuminance(),
    );
    expect(
      (hi + 0.05) / (lo + 0.05),
      greaterThanOrEqualTo(4.5),
      reason: 'the recovery words must be readable',
    );

    final words = _mnemonic.split(' ');
    for (final index in const [0, 5, 11]) {
      final field = find.widgetWithText(TextField, 'Word #${index + 1}');
      await tester.ensureVisible(field);
      await tester.enterText(field, words[index]);
    }
    await frames(tester, 2);
    await tester.ensureVisible(find.text('Complete Setup'));
    await tester.tap(find.text('Complete Setup'));
    await frames(tester, 20);

    expect(location(tester), '/collect');
    expect(find.text('Collect'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clean install: passkey, then on to Collect, claiming nothing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final browser = await launch(tester);
    await toWalletChoice(tester);

    await tester.tap(find.byKey(const Key('welcome-use-passkey')));
    await frames(tester);
    expect(location(tester), '/wallet/passkey');

    await tester.tap(find.byKey(const Key('passkey-open-page')));
    await frames(tester, 2);
    expect(browser.opened, 1);
    expect(find.textContaining('need a 12-word wallet'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('passkey-continue')));
    await tester.tap(find.byKey(const Key('passkey-continue')));
    await frames(tester);
    expect(location(tester), '/collect');
    expect(
      find.text('Create or import a wallet to see reward totals.'),
      findsOneWidget,
      reason: 'a passkey wallet is not a wallet this app holds',
    );
  });

  testWidgets('clean install: import goes to its screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await launch(tester);
    await toWalletChoice(tester);

    await tester.tap(find.byKey(const Key('welcome-import-wallet')));
    await frames(tester);
    expect(location(tester), '/wallet/import');
  });

  testWidgets('Skip leaves first run for good', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await launch(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Skip'));
    await frames(tester);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(location(tester), '/weather');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('welcome.seen'), isTrue);
  });

  testWidgets('a returning phone never sees the welcome', (tester) async {
    SharedPreferences.setMockInitialValues({'welcome.seen': true});
    await launch(tester);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(location(tester), '/weather');
  });

  testWidgets('an update on a phone with a wallet never sees the welcome', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await launch(tester, withWallet: true);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(location(tester), '/weather');
  });

  testWidgets('the done location honours only Collect', (tester) async {
    SharedPreferences.setMockInitialValues({'welcome.seen': true});
    await launch(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>).first),
    );
    final GoRouter router = container.read(appRouterProvider);
    router.go('/wallet/create?then=https://example.com');
    await frames(tester);
    expect(location(tester), '/wallet/create');
    expect(find.text('Generate Wallet'), findsOneWidget);
  });
}
