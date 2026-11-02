import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/passkey_wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/passkey_wallet_screen.dart';

import '../../../../test_helpers/fakes.dart';

const _address = '0x59b3000000000000000000000000000000f057a1';

class _NoPhoneWallet extends WalletNotifier {
  @override
  Future<WalletModel?> build() async => null;
}

class _Balance extends FakeWalletRepository {
  _Balance(this.answer);
  final Either<Failure, WalletModel> Function(String) answer;
  final asked = <String>[];

  @override
  Future<Either<Failure, WalletModel>> getWallet(String address) async {
    asked.add(address);
    return answer(address);
  }
}

class _RecordingBrowser extends PasskeyBrowser {
  _RecordingBrowser({this.result = true});
  final bool result;
  int opened = 0;

  @override
  Future<bool> open() async {
    opened++;
    return result;
  }
}

void main() {
  late String? clipboard;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        });
  });

  Future<void> pump(
    WidgetTester tester, {
    PasskeyBrowser? browser,
    _Balance? repository,
  }) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const PasskeyWalletScreen()),
        GoRoute(
          path: '/wallet/create',
          builder: (_, _) => const Text('create screen'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walletProvider.overrideWith(_NoPhoneWallet.new),
          passkeyBrowserProvider.overrideWithValue(
            browser ?? _RecordingBrowser(),
          ),
          walletRepositoryProvider.overrideWithValue(
            repository ??
                _Balance(
                  (a) => Right(WalletModel(address: a, balance: '150000000')),
                ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('opening the page', () {
    testWidgets('the button opens the browser tab', (tester) async {
      final browser = _RecordingBrowser();
      await pump(tester, browser: browser);
      await tester.tap(find.byKey(const Key('passkey-open-page')));
      await tester.pumpAndSettle();
      expect(browser.opened, 1);
      expect(find.byKey(const Key('passkey-open-failed')), findsNothing);
    });

    testWidgets('no browser: says where to go instead', (tester) async {
      await pump(tester, browser: _RecordingBrowser(result: false));
      await tester.tap(find.byKey(const Key('passkey-open-page')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('passkey-open-failed')), findsOneWidget);
    });

    test('tries the in-app tab first, then the browser', () async {
      final modes = <LaunchMode>[];
      final urls = <Uri>[];
      final browser = PasskeyBrowser(
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          modes.add(mode);
          urls.add(url);
          if (mode == LaunchMode.inAppBrowserView) throw StateError('no tab');
          return true;
        },
      );
      expect(await browser.open(), isTrue);
      expect(modes, [
        LaunchMode.inAppBrowserView,
        LaunchMode.externalApplication,
      ]);
      expect(
        urls.toSet().single.toString(),
        'https://wrfcoin.com/wallet/passkey',
      );
    });

    test('nothing can open it: false, not a throw', () async {
      final browser = PasskeyBrowser(
        launch: (url, {mode = LaunchMode.platformDefault}) async => false,
      );
      expect(await browser.open(), isFalse);
    });
  });

  group('bringing the address back', () {
    testWidgets('Paste fills in an address, Save shows it as view only', (
      tester,
    ) async {
      final repository = _Balance(
        (a) => Right(WalletModel(address: a, balance: '150000000')),
      );
      await pump(tester, repository: repository);
      clipboard = ' ${_address.toUpperCase().replaceFirst('0X', '0x')} ';
      await tester.tap(find.byKey(const Key('passkey-paste')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('passkey-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('passkey-view-only')), findsOneWidget);
      expect(find.text(_address), findsOneWidget, reason: 'stored lowercase');
      expect(repository.asked, [_address]);
      expect(find.text('1.5 WRF'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PasskeyAddressNotifier.storageKey), _address);
    });

    testWidgets('a clipboard without an address never reaches the screen', (
      tester,
    ) async {
      await pump(tester);
      clipboard = 'abandon ability able about above absent absorb abstract';
      await tester.tap(find.byKey(const Key('passkey-paste')));
      await tester.pumpAndSettle();

      expect(find.textContaining('abandon'), findsNothing);
      expect(
        find.text("The clipboard doesn't hold a wallet address."),
        findsOneWidget,
      );
    });

    testWidgets('a typed non-address is refused and nothing is saved', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(
        find.byKey(const Key('passkey-address-field')),
        'not-an-address',
      );
      await tester.tap(find.byKey(const Key('passkey-save')));
      await tester.pumpAndSettle();

      expect(find.text('That is not a 0x… wallet address.'), findsOneWidget);
      expect(find.byKey(const Key('passkey-view-only')), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PasskeyAddressNotifier.storageKey), isNull);
    });

    testWidgets('a failed balance read never shows a number', (tester) async {
      SharedPreferences.setMockInitialValues({
        PasskeyAddressNotifier.storageKey: _address,
      });
      await pump(
        tester,
        repository: _Balance((_) => const Left(ServerFailure('down'))),
      );
      await tester.pump(const Duration(seconds: 1));
      final balance = tester.widget<Text>(
        find.byKey(const Key('passkey-balance')),
      );
      expect(balance.data, isNot(contains('WRF')));
    });

    testWidgets('Remove forgets the address', (tester) async {
      SharedPreferences.setMockInitialValues({
        PasskeyAddressNotifier.storageKey: _address,
      });
      await pump(tester);
      await tester.ensureVisible(find.byKey(const Key('passkey-remove')));
      await tester.tap(find.byKey(const Key('passkey-remove')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('passkey-view-only')), findsNothing);
      expect(find.byKey(const Key('passkey-address-field')), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PasskeyAddressNotifier.storageKey), isNull);
    });

    test('a corrupt saved value reads as nothing saved', () async {
      SharedPreferences.setMockInitialValues({
        PasskeyAddressNotifier.storageKey: 'garbage',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(passkeyAddressProvider.future), isNull);
    });
  });

  group('what it says', () {
    testWidgets('states the limits, and never claims a sign-in', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        PasskeyAddressNotifier.storageKey: _address,
      });
      await pump(tester);

      expect(find.byKey(const Key('passkey-limits')), findsOneWidget);
      expect(find.textContaining("so it can't send or sign"), findsOneWidget);
      expect(find.textContaining('need a 12-word wallet'), findsOneWidget);
      expect(find.textContaining('Signed in'), findsNothing);
      expect(find.textContaining('signed in'), findsNothing);
      expect(find.text('Send'), findsNothing);
    });

    testWidgets('offers a 12-word wallet for collecting', (tester) async {
      await pump(tester);
      await tester.ensureVisible(
        find.byKey(const Key('passkey-add-phone-wallet')),
      );
      await tester.tap(find.byKey(const Key('passkey-add-phone-wallet')));
      await tester.pumpAndSettle();
      expect(find.text('create screen'), findsOneWidget);
    });
  });
}
