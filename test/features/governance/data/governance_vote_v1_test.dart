import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/proposal_model.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/vote_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/services/api/api_client.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/governance_vote_signing.dart';

import '../../../test_helpers/fakes.dart';

// Synthetic seed [7;32], independently pinned by backend/core4 station vectors.
const seed = '0707070707070707070707070707070707070707070707070707070707070707';
const publicKey =
    'ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c';
const address = '0x791026e25cc1ba461167ffb5c6dc095c284bd92c';
List<int> unhex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

class CancellingAuthClient extends FakeLocalAuthClient {
  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    authenticateBiometricOnlyCalls.add(biometricOnly);
    throw LocalAuthException(code: LocalAuthExceptionCode.userCanceled);
  }
}

class CountingStorage extends InMemoryKeyValueStorage {
  int privateReads = 0;
  @override
  Future<String?> read({required String key}) {
    if (key == 'wrf_private_key') privateReads++;
    return super.read(key: key);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late CountingStorage storage;
  late FakeLocalAuthClient auth;
  late KeyManager keys;
  late List<RequestOptions> requests;
  late ProviderContainer container;
  Future<void> setup({
    bool allowed = true,
    bool foreground = true,
    String keyAddress = address,
    String scheme = KeyManager.canonicalKeyScheme,
    bool signedIn = true,
    String? loginAddress,
  }) async {
    LoginAttemptGuard.resetIsolateStateForTest();
    storage = CountingStorage();
    auth = allowed ? FakeLocalAuthClient() : CancellingAuthClient();
    keys = KeyManager(
      biometric: BiometricService(client: auth),
      storage: storage,
    );
    await keys.storeKeys(
      mnemonic: 'synthetic',
      privateKey: seed,
      address: keyAddress,
      keyScheme: scheme,
      loginAddress: loginAddress,
    );
    requests = [];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            requests.add(o);
            h.resolve(Response(requestOptions: o, data: {'success': true}));
          },
        ),
      );
    container = ProviderContainer(
      overrides: [
        keyManagerProvider.overrideWithValue(keys),
        apiClientProvider.overrideWithValue(
          ApiClient(dio: dio, allowUnauthenticatedRequests: signedIn),
        ),
      ],
    );
    binding.handleAppLifecycleStateChanged(
      foreground ? AppLifecycleState.resumed : AppLifecycleState.paused,
    );
  }

  tearDown(() => container.dispose());
  for (final choice in ['FOR', 'AGAINST']) {
    test('$choice production provider sends verified raw v1 signature', () async {
      await setup();
      final result = await container
          .read(governanceRepositoryProvider)
          .vote(
            proposalId: 'proposal-1',
            voteType: choice,
            reason: 'Synthetic rationale',
          );
      expect(result.isRight(), isTrue);
      expect(requests, hasLength(1));
      final body = Map<String, dynamic>.from(requests.single.data as Map);
      expect(
        body.keys,
        unorderedEquals([
          'voteType',
          'reason',
          'signer_public_key',
          'signature',
        ]),
      );
      expect(body['signer_public_key'], publicKey);
      final fixture = jsonDecode(
        File('test/fixtures/governance-vote-v1.json').readAsStringSync(),
      ) as Map;
      final golden = (fixture['vectors'] as List).cast<Map>().singleWhere(
        (v) => v['choice'] == (choice == 'FOR' ? 'approve' : 'reject'),
      );
      expect(body['signature'], golden['signature']);
      expect(
        body['signature'],
        isA<String>().having((s) => s.length, 'length', 128),
      );
      final message = utf8.encode(
        'governance-vote-v1|proposal-1|${choice == 'FOR' ? 'approve' : 'reject'}',
      );
      if (choice == 'FOR') {
        expect(
          message.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          '676f7665726e616e63652d766f74652d76317c70726f706f73616c2d317c617070726f7665',
        );
      }
      expect(
        await Ed25519().verify(
          message,
          signature: Signature(
            unhex(body['signature'] as String),
            publicKey: SimplePublicKey(
              unhex(publicKey),
              type: KeyPairType.ed25519,
            ),
          ),
        ),
        isTrue,
      );
      expect(storage.privateReads, 1);
      expect(auth.authenticateBiometricOnlyCalls, hasLength(1));
    });
  }
  for (final scenario in [
    'biometric denied',
    'background',
    'mismatched address',
    'legacy wallet',
    'ABSTAIN',
    'invalid proposal',
    'not signed in',
    'login address mismatch',
  ]) {
    test('$scenario sends nothing and returns failure', () async {
      await setup(
        allowed: scenario != 'biometric denied',
        signedIn: scenario != 'not signed in',
        loginAddress: scenario == 'login address mismatch'
            ? '0x${'2' * 40}'
            : null,
        foreground: scenario != 'background',
        keyAddress: scenario == 'mismatched address'
            ? '0x${'1' * 40}'
            : address,
        scheme: scenario == 'legacy wallet'
            ? KeyManager.legacyKeyScheme
            : KeyManager.canonicalKeyScheme,
      );
      final result = await container
          .read(governanceRepositoryProvider)
          .vote(
            proposalId: scenario == 'invalid proposal'
                ? 'proposal|reject'
                : 'proposal-1',
            voteType: scenario == 'ABSTAIN' ? 'ABSTAIN' : 'FOR',
          );
      expect(result.isLeft(), isTrue);
      expect(requests, isEmpty);
      if ([
        'background',
        'legacy wallet',
        'ABSTAIN',
        'invalid proposal',
        'not signed in',
        'login address mismatch',
      ].contains(scenario)) {
        expect(storage.privateReads, 0);
      }
    });
  }
  test(
    'unsupported configured version sends nothing without opening key',
    () async {
      await setup();
      final api = container.read(apiClientProvider);
      final repo = GovernanceRepository(
        api.dio,
        signer: GovernanceVoteSigner(
          keyManager: keys,
          version: 2,
          isForeground: () => true,
        ),
        ensureAuthenticated: api.ensureWalletSession,
      );
      final result = await repo.vote(proposalId: 'proposal-1', voteType: 'FOR');
      expect(result.isLeft(), isTrue);
      expect(requests, isEmpty);
      expect(storage.privateReads, 0);
    },
  );
  for (final allowed in [true, false]) {
    testWidgets(
      'confirmed screen vote authenticates the wallet once (allowed=$allowed)',
      (tester) async {
        await setup(allowed: allowed);
        const proposal = ProposalModel(
          id: 'proposal-1',
          title: 'Synthetic',
          description: 'Test',
          proposalType: 'platform_upgrade',
          status: 'active',
          votesFor: 0,
          votesAgainst: 0,
          votesAbstain: 0,
        );
        final router = GoRouter(
          initialLocation: '/vote',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('Parent')),
              routes: [
                GoRoute(
                  path: 'vote',
                  builder: (_, _) => const VoteScreen(proposal: proposal),
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Vote For'));
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Vote'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(auth.authenticateBiometricOnlyCalls, isEmpty);
        await tester.runAsync(() async {
          await tester.tap(find.widgetWithText(TextButton, 'Cast Vote'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump(const Duration(milliseconds: 300));
        expect(auth.authenticateBiometricOnlyCalls, hasLength(1));
        expect(
          requests.where((r) => r.method == 'POST'),
          hasLength(allowed ? 1 : 0),
        );
        expect(storage.privateReads, allowed ? 1 : 0);
        expect(find.text(allowed ? 'Parent' : 'Synthetic'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      },
    );
  }
}
