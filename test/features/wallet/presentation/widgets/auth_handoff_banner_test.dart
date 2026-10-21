import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/widgets/auth_handoff_banner.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(dio: Dio());

  int signIns = 0;
  int ensures = 0;
  bool throwOnSignIn = false;

  @override
  Future<bool> signInNow() async {
    signIns++;
    if (throwOnSignIn) throw StateError('boom (test)');
    return true;
  }

  @override
  Future<bool> ensureWalletSession() async {
    ensures++;
    return true;
  }
}

void main() {
  late _RecordingApiClient api;
  late AuthHandoffController handoff;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: handoff,
              builder: (_, _) => AuthHandoffBanner(handoff: handoff),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    api = _RecordingApiClient();
    handoff = AuthHandoffController();
  });

  testWidgets(
    'a session hold offers "Sign in again", which is the explicit sign-in',
    (tester) async {
      handoff.requireWalletConnect(
        reason: AuthHandoffReason.sessionExpired,
        message: 'Automatic sign-in is paused to protect the login limit.',
      );
      await pump(tester);

      expect(find.text('Sign in again'), findsOneWidget);
      await tester.tap(find.byKey(const Key('auth-handoff-sign-in')));
      await tester.pumpAndSettle();

      expect(api.signIns, 1);
      expect(
        api.ensures,
        0,
        reason: 'the button must use the user-initiated path',
      );
    },
  );

  testWidgets('Dismiss hides the message without signing in', (tester) async {
    handoff.requireWalletConnect(
      reason: AuthHandoffReason.sessionExpired,
      message: 'Wallet authentication failed.',
    );
    await pump(tester);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text('Wallet authentication failed.'), findsNothing);
    expect(api.signIns, 0);
    expect(api.ensures, 0);
  });

  testWidgets(
    'an unsupported wallet offers no sign-in (it needs a re-import)',
    (tester) async {
      handoff.requireWalletConnect(
        reason: AuthHandoffReason.unsupportedWallet,
        message: 'Wallet address does not match its signing key.',
      );
      await pump(tester);

      expect(find.text('Sign in again'), findsNothing);
    },
  );

  testWidgets('the button is usable again even if sign-in throws', (
    tester,
  ) async {
    api.throwOnSignIn = true;
    handoff.requireWalletConnect(
      reason: AuthHandoffReason.sessionExpired,
      message: 'Automatic sign-in is paused.',
    );
    await pump(tester);

    await tester.tap(find.byKey(const Key('auth-handoff-sign-in')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final button = tester.widget<TextButton>(
      find.byKey(const Key('auth-handoff-sign-in')),
    );
    expect(button.onPressed, isNotNull);
    expect(api.signIns, 1);
  });
}
