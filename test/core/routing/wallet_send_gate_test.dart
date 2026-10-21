import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/build_flags.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/send_screen.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';

/// Owner ruling 2026-09-27 (mobile#44): sends are not enabled for testers,
/// so tester (profile) builds hide Send by default. The send-on cases are
/// the control: they prove the finders and the route can see Send when it
/// is reachable.
void main() {
  group('WalletSendGate.resolve', () {
    test(
      'profile builds hide Send by default; debug and release are unchanged',
      () {
        expect(
          WalletSendGate.resolve(override: '', isProfileMode: true),
          isFalse,
        );
        expect(
          WalletSendGate.resolve(override: '', isProfileMode: false),
          isTrue,
        );
      },
    );

    test('the dart-define overrides the default in either direction', () {
      expect(
        WalletSendGate.resolve(override: 'on', isProfileMode: true),
        isTrue,
      );
      expect(
        WalletSendGate.resolve(override: 'ON ', isProfileMode: true),
        isTrue,
      );
      expect(
        WalletSendGate.resolve(override: 'off', isProfileMode: false),
        isFalse,
      );
    });

    test('an unrecognised value fails closed', () {
      for (final v in ['true', '1', 'yes', 'enabled', 'o n']) {
        expect(
          WalletSendGate.resolve(override: v, isProfileMode: false),
          isFalse,
          reason: v,
        );
      }
    });

    test('this test binary is not a profile build, so the default is on', () {
      expect(WalletSendGate.enabled, isTrue);
    });
  });

  group('wallet app', () {
    late AppDatabase db;

    setUp(() => db = createTestDatabase());
    tearDown(() async => db.close());

    Future<GoRouter> pumpApp(WidgetTester tester, {required bool send}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(
        await buildTestApp(
          db: db,
          // These tests are about the loaded wallet tab.
          signedIn: true,
          extraOverrides: [walletSendEnabledProvider.overrideWithValue(send)],
        ),
      );
      await pumpFrames(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Router<Object>).first),
      );
      return container.read(appRouterProvider);
    }

    String currentPath(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.path;

    final receiveButton = find.text('Receive', skipOffstage: false);
    final sendButton = find.widgetWithText(
      ElevatedButton,
      'Send',
      skipOffstage: false,
    );

    testWidgets('send off: the wallet tab offers no Send button', (
      tester,
    ) async {
      final router = await pumpApp(tester, send: false);
      router.go('/wallet');
      await pumpUntilFound(tester, receiveButton);

      expect(sendButton, findsNothing);
    });

    testWidgets(
      'send off: /wallet/send (deep link or push) redirects to /wallet',
      (tester) async {
        final router = await pumpApp(tester, send: false);
        router.go('/wallet/send');
        await pumpUntilFound(tester, receiveButton);

        expect(currentPath(router), '/wallet');
        expect(find.byType(SendScreen, skipOffstage: false), findsNothing);

        router.go('/wallet');
        await pumpUntilFound(tester, receiveButton);
        unawaited(router.push('/wallet/send'));
        await pumpFrames(tester);
        expect(find.byType(SendScreen, skipOffstage: false), findsNothing);
      },
    );

    testWidgets('send on (control): the wallet tab shows Send', (tester) async {
      final router = await pumpApp(tester, send: true);
      router.go('/wallet');
      await pumpUntilFound(tester, receiveButton);

      expect(sendButton, findsOneWidget);
    });

    testWidgets('send on (control): /wallet/send builds the send screen', (
      tester,
    ) async {
      final router = await pumpApp(tester, send: true);
      router.go('/wallet/send');
      await pumpUntilFound(tester, find.byType(SendScreen));

      expect(currentPath(router), '/wallet/send');
    });
  });

  testWidgets('send off: a SendScreen built any other way shows no send form', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [walletSendEnabledProvider.overrideWithValue(false)],
        child: const MaterialApp(home: SendScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('wallet-send-disabled')), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
