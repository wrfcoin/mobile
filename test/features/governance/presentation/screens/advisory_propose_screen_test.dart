import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/advisory_propose_screen.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_list_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/advisory_action_signing.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/transfer_signing_domain.dart';

import '../../../../test_helpers/fakes.dart';
import '../../fixtures/advisory_api.dart';

const seed = '4242424242424242424242424242424242424242424242424242424242424242';
const address = '0xa307fb31c7585b6ccb5dc3ddc844e22b14b7aa0d';
const deposit =
    'Proposing holds 1 WRF from this wallet. It comes back when the vote is '
    'decided, and stays held if fewer than 3 wallets vote.';

class Setup {
  Setup(this.api, this.auth, this.widget);
  final FakeAdvisoryApi api;
  final FakeLocalAuthClient auth;
  final Widget widget;
  int get unlocks => auth.authenticateBiometricOnlyCalls.length;
  Iterable<String> get posts => api.calls.where((c) => c.startsWith('POST'));
}

Future<Setup> setup({
  bool unlock = true,
  String scheme = KeyManager.canonicalKeyScheme,
  int actionStatus = 202,
  Object? actionBody,
  String? balance = '10900000000',
  int nonce = 0,
}) async {
  LoginAttemptGuard.resetIsolateStateForTest();
  final auth = FakeLocalAuthClient(authenticateResult: unlock);
  final keys = KeyManager(
    biometric: BiometricService(client: auth),
    storage: InMemoryKeyValueStorage(),
  );
  await keys.storeKeys(
    mnemonic: 'never read by a proposal',
    privateKey: seed,
    address: address,
    keyScheme: scheme,
  );
  final api = FakeAdvisoryApi(
    [welcomeProposalJson()],
    actionStatus: actionStatus,
    actionBody: actionBody,
    balance: balance,
    nonce: nonce,
  );
  final repo = GovernanceRepository(
    api.dio(),
    advisorySigner: AdvisoryActionSigner(
      keyManager: keys,
      domain: const TransferSigningDomain(chainId: '888', networkId: 'testnet'),
      isForeground: () => true,
    ),
  );
  return Setup(
    api,
    auth,
    ProviderScope(
      overrides: [governanceRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: ProposalListScreen()),
    ),
  );
}

Future<void> openForm(WidgetTester tester, Setup s) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(s.widget);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('advisory-new-proposal')));
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String title, String summary) async {
  await tester.enterText(find.byKey(const Key('advisory-title')), title);
  await tester.enterText(find.byKey(const Key('advisory-summary')), summary);
  await tester.pumpAndSettle();
}

FilledButton review(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const Key('advisory-propose-review')),
);

Future<void> submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('advisory-propose-review')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('sheet-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('New proposal: live byte counters, the sheet states the '
      'deposit, one unlock, the exact core4 body, "Sent"', (tester) async {
    final s = await setup();
    await openForm(tester, s);

    expect(find.text('0 / 160 bytes, one line'), findsOneWidget);
    expect(find.text('0 / 1024 bytes'), findsOneWidget);
    expect(find.text(deposit), findsOneWidget);
    expect(review(tester).onPressed, isNull);

    // The core4 vector's text: "é" is 2 bytes and the emoji 4.
    await fill(tester, 'Welcome, café 🌧', 'Line one.\nLine two.');
    expect(find.text('19 / 160 bytes, one line'), findsOneWidget);
    expect(find.text('19 / 1024 bytes'), findsOneWidget);
    expect(review(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('advisory-propose-review')));
    await tester.pumpAndSettle();
    String sel(String k) =>
        tester.widget<SelectableText>(find.byKey(Key(k))).data!;
    expect(find.byKey(const Key('advisory-propose-sheet')), findsOneWidget);
    expect(sel('sheet-title'), 'Welcome, café 🌧');
    expect(sel('sheet-summary'), 'Line one.\nLine two.');
    expect(sel('sheet-wallet'), address);
    expect(
      tester.widget<Text>(find.byKey(const Key('sheet-deposit'))).data,
      deposit,
    );
    expect(s.unlocks, 0);
    expect(s.posts, isEmpty);

    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();
    expect(s.unlocks, 1);
    final vectors = jsonDecode(
      File('test/services/crypto/advisory_governance_vectors.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final c = (vectors['cases'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['name'] == 'ed25519_propose');
    expect(jsonEncode(s.api.posted.single), c['data']);
    expect(find.text(advisoryProposeSentNote), findsOneWidget);
    expect(find.textContaining('77 seconds'), findsOneWidget);
    expect(find.text('Proposal adv-bb41213ed8b391ca'), findsOneWidget);

    // Back on the list, it was read again.
    await tester.tap(find.text('Back to proposals'));
    await tester.pumpAndSettle();
    expect(
      s.api.calls
          .where((c) => c.startsWith('GET /api/governance/advisory/proposals?'))
          .length,
      2,
    );
  });

  testWidgets('a text problem shows the website wording and blocks review', (
    tester,
  ) async {
    final s = await setup();
    await openForm(tester, s);
    await fill(tester, 'T', 'x' * 1025);
    expect(
      find.text('The summary is 1025 bytes; the limit is 1024.'),
      findsOneWidget,
    );
    expect(review(tester).onPressed, isNull);
  });

  testWidgets('cancel on the sheet: no unlock, nothing sent', (tester) async {
    final s = await setup();
    await openForm(tester, s);
    await fill(tester, 'T', 'S');
    await tester.tap(find.byKey(const Key('advisory-propose-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-cancel')));
    await tester.pumpAndSettle();
    expect(s.unlocks, 0);
    expect(s.posts, isEmpty);
  });

  testWidgets('the unlock gate is required: refused unlock sends nothing', (
    tester,
  ) async {
    final s = await setup(unlock: false);
    await openForm(tester, s);
    await fill(tester, 'T', 'S');
    await submit(tester);
    expect(s.unlocks, 1);
    expect(s.posts, isEmpty);
    expect(find.text('Unlock cancelled. Nothing was sent.'), findsOneWidget);
  });

  testWidgets('under 1 WRF: refused plainly, no unlock', (tester) async {
    final s = await setup(balance: '50000000');
    await openForm(tester, s);
    await fill(tester, 'T', 'S');
    await submit(tester);
    expect(
      find.text(
        'This wallet has under 1 WRF it can spend. Proposing holds 1 WRF, so '
        "it can't propose yet. Nothing was sent.",
      ),
      findsOneWidget,
    );
    expect(s.unlocks, 0);
    expect(s.posts, isEmpty);
  });

  testWidgets('relay refusal in plain words (open proposal already)', (
    tester,
  ) async {
    final s = await setup(
      actionStatus: 422,
      actionBody: errorBody(
        'ADVISORY_GOVERNANCE_REFUSED',
        'SP_ADVISORY_GOVERNANCE_REFUSED: this wallet already has an active '
            'proposal',
      ),
    );
    await openForm(tester, s);
    await fill(tester, 'T', 'S');
    await submit(tester);
    expect(
      find.text(
        'This wallet already has a proposal open. It can propose again once '
        'that one is decided.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('older wallet type: can\'t propose yet, no form', (tester) async {
    final s = await setup(scheme: KeyManager.legacyKeyScheme);
    await openForm(tester, s);
    expect(find.text("This wallet type can't propose yet."), findsOneWidget);
    expect(find.byKey(const Key('advisory-title')), findsNothing);
    expect(find.textContaining('wrfcoin.com'), findsNothing);
  });
}
