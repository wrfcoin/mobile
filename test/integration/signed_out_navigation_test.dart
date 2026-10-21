// mobile#320 review P1-1: a wallet without a session is "Not signed in" on
// Earnings only. The rest of the app stays usable: tapping Collect lands on
// /collect and stays there, no tab bounces to /wallet, and being signed out
// never costs a biometric prompt or a login request.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart' show BiometricType;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../test_helpers/app_harness.dart';

/// Counts auth requests; every other route answers 401 (no session).
class _Backend implements HttpClientAdapter {
  int nonceGets = 0;
  int loginPosts = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.contains('/auth/nonce/')) nonceGets++;
    if (path.endsWith('/auth/wallet-login')) loginPosts++;
    return ResponseBody.fromString(
      jsonEncode({'error': 'unauthorized'}),
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _CountingLocalAuth implements LocalAuthClient {
  int prompts = 0;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    prompts++;
    return true;
  }

  @override
  Future<bool> canCheckBiometrics() async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [
    BiometricType.strong,
  ];
}

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  testWidgets(
    'a stored wallet with no session: Collect stays on /collect, other tabs '
    'stay reachable, Earnings says Not signed in, 0 nonce and 0 prompts',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final backend = _Backend();
      final localAuth = _CountingLocalAuth();

      await tester.pumpWidget(
        await buildTestApp(
          db: db,
          localAuthClient: localAuth,
          extraOverrides: [
            // The production client (interceptor, 401 retry, automatic
            // session checks) over a backend that counts auth requests.
            apiClientProvider.overrideWith((ref) {
              final authDio = Dio(
                BaseOptions(baseUrl: 'https://backend.test/api'),
              )..httpClientAdapter = backend;
              final client = ApiClient(
                authDio: authDio,
                keyManager: ref.read(keyManagerProvider),
                authHandoff: ref.read(authHandoffControllerProvider),
              );
              client.dio.options.baseUrl = 'https://backend.test/api';
              client.dio.httpClientAdapter = backend;
              return client;
            }),
          ],
        ),
      );
      await pumpFrames(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Router<Object>).first),
      );
      final GoRouter router = container.read(appRouterProvider);
      String path() => router.routerDelegate.currentConfiguration.uri.path;

      await tester.tap(find.text('Collect'));
      await pumpUntilFound(tester, find.text('Sync Progress & Rewards'));
      await pumpFrames(tester, frames: 10);
      expect(path(), '/collect');
      expect(find.byType(Switch), findsWidgets);

      await tester.tap(find.text('Earnings'));
      await pumpUntilFound(tester, find.text('Not signed in'));
      expect(path(), '/wallet');
      final handoff = container.read(authHandoffControllerProvider);
      expect(handoff.reason, AuthHandoffReason.notSignedIn);

      // Signed out is not a reason to be sent back to the wallet.
      await tester.tap(find.text('Weather'));
      await pumpFrames(tester, frames: 10);
      expect(path(), '/weather');
      await tester.tap(find.text('Collect'));
      await pumpUntilFound(tester, find.text('Sync Progress & Rewards'));
      await pumpFrames(tester, frames: 10);
      expect(path(), '/collect');

      expect(backend.nonceGets, 0);
      expect(backend.loginPosts, 0);
      expect(localAuth.prompts, 0);
    },
  );
  testWidgets(
    'guard: a real session problem (sessionExpired, unsupportedWallet) still '
    'sends the user to the wallet',
    (tester) async {
      for (final reason in const [
        AuthHandoffReason.sessionExpired,
        AuthHandoffReason.unsupportedWallet,
      ]) {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        await tester.pumpWidget(await buildTestApp(db: db, signedIn: true));
        await pumpFrames(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(Router<Object>).first),
        );
        final GoRouter router = container.read(appRouterProvider);
        String path() => router.routerDelegate.currentConfiguration.uri.path;

        await tester.tap(find.text('Collect'));
        await pumpUntilFound(tester, find.text('Sync Progress & Rewards'));
        expect(path(), '/collect');

        container
            .read(authHandoffControllerProvider)
            .requireWalletConnect(reason: reason, message: 'Reconnect (test)');
        await pumpFrames(tester);
        expect(path(), '/wallet', reason: reason.name);

        await tester.pumpWidget(const SizedBox.shrink());
        await pumpFrames(tester);
      }
    },
  );
}
