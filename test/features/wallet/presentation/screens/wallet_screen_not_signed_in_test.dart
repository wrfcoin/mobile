// mobile#320: Earnings for a wallet that has no session says "Not signed in"
// and offers Sign in. It never says "Session expired" for a session that
// never existed, and never "No Wallet Found" for a wallet that exists.
import 'package:fpdart/fpdart.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_page.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/wallet_model.dart';
import 'package:wrfcoin_mobile/features/wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/wallet_screen.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/wallet_secure_storage.dart';

import '../../../../test_helpers/fakes.dart';

const _address = 'wrf1testwallet0000000000';

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient(this.handoff) : super(dio: Dio());

  final AuthHandoffController handoff;
  int signIns = 0;
  bool signedIn = false;

  @override
  Future<bool> signInNow() async {
    signIns++;
    signedIn = true;
    handoff.clear();
    return true;
  }

  @override
  Future<bool> ensureWalletSession() async => signedIn;
}

/// The wallet routes answer 401 until [_RecordingApiClient.signedIn].
class _AuthGatedRepository extends FakeWalletRepository {
  _AuthGatedRepository(this.api);

  final _RecordingApiClient api;
  int walletRequests = 0;

  @override
  Future<Either<Failure, WalletModel>> getWallet(String address) async {
    walletRequests++;
    if (!api.signedIn) {
      return const Left(AuthFailure('Session expired. Please sign in again.'));
    }
    return super.getWallet(address);
  }

  @override
  Future<Either<Failure, TransactionPage>> getTransactions(
    String address, {
    int offset = 0,
    int limit = 20,
    String? creditAfter,
    CancelToken? cancelToken,
  }) async {
    if (!api.signedIn) {
      return const Left(AuthFailure('Session expired. Please sign in again.'));
    }
    return super.getTransactions(
      address,
      offset: offset,
      limit: limit,
      creditAfter: creditAfter,
      cancelToken: cancelToken,
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<
  ({
    _RecordingApiClient api,
    AuthHandoffController handoff,
    _AuthGatedRepository repo,
  })
>
_pump(WidgetTester tester, {bool raiseHandoff = false}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final keyStorage = InMemoryKeyValueStorage();
  await keyStorage.write(key: 'wrf_address', value: _address);
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final handoff = AuthHandoffController();
  if (raiseHandoff) {
    handoff.requireWalletConnect(
      reason: AuthHandoffReason.notSignedIn,
      message: 'Not signed in. Tap Sign in to continue.',
    );
  }
  final api = _RecordingApiClient(handoff);
  final repo = _AuthGatedRepository(api);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(api),
        authHandoffControllerProvider.overrideWith((ref) => handoff),
        walletRepositoryProvider.overrideWithValue(repo),
        keyManagerProvider.overrideWithValue(
          KeyManager(
            biometric: BiometricService(client: FakeLocalAuthClient()),
            storage: keyStorage,
          ),
        ),
        walletSecureStorageProvider.overrideWithValue(
          FakeWalletSecureStorage(backupConfirmed: true),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/wallet',
          routes: [
            GoRoute(path: '/wallet', builder: (_, _) => const WalletScreen()),
          ],
        ),
      ),
    ),
  );
  await _settle(tester);
  return (api: api, handoff: handoff, repo: repo);
}

void main() {
  testWidgets('a 401 on Earnings shows "Not signed in" with Sign in', (
    tester,
  ) async {
    final ctx = await _pump(tester);

    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.textContaining('Session expired'), findsNothing);
    expect(find.text('No Wallet Found'), findsNothing);

    // Riverpod's automatic retry would repeat the 401 ~10 times over ~40 s.
    await tester.pump(const Duration(seconds: 45));
    expect(ctx.repo.walletRequests, 1);

    await tester.tap(find.byKey(const Key('wallet-sign-in')));
    await _settle(tester);

    expect(ctx.api.signIns, 1);
    expect(find.text('Not signed in'), findsNothing);
    expect(find.textContaining('42'), findsWidgets);
  });

  testWidgets(
    'a sign-in handoff for an existing wallet is "Not signed in", not '
    '"No Wallet Found"',
    (tester) async {
      final ctx = await _pump(tester, raiseHandoff: true);

      expect(find.text('No Wallet Found'), findsNothing);
      expect(find.text('Not signed in'), findsOneWidget);
      // One Sign in action on the screen, not a banner plus a card.
      expect(find.byKey(const Key('wallet-sign-in')), findsOneWidget);
      expect(find.byKey(const Key('auth-handoff-sign-in')), findsNothing);

      await tester.tap(find.byKey(const Key('wallet-sign-in')));
      await _settle(tester);
      expect(ctx.api.signIns, 1);
    },
  );
}
