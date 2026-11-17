import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/advisory_vote.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_detail_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/advisory_action_signing.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/transfer_signing_domain.dart';

import '../../../../test_helpers/fakes.dart';
import '../../fixtures/advisory_api.dart';

// The website/core4 vector wallet (seed 0x42 x 32).
const seed = '4242424242424242424242424242424242424242424242424242424242424242';
const address = '0xa307fb31c7585b6ccb5dc3ddc844e22b14b7aa0d';
const id = 'adv-a75dae543f5f9e16';
const eligibilityCall =
    'GET /api/governance/advisory/proposals/$id/eligibility?address=$address';

class Setup {
  Setup(this.api, this.auth, this.widget);
  final FakeAdvisoryApi api;
  final FakeLocalAuthClient auth;
  final Widget widget;
  int get unlocks => auth.authenticateBiometricOnlyCalls.length;
  Iterable<String> get posts => api.calls.where((c) => c.startsWith('POST'));
}

Future<Setup> setup({
  Map<String, dynamic>? eligibility,
  Map<String, dynamic>? proposal,
  bool unlock = true,
  String scheme = KeyManager.canonicalKeyScheme,
  int actionStatus = 202,
  Object? actionBody,
  DioExceptionType? actionTransportError,
  String proposalId = id,
}) async {
  // storeKeys serializes through an isolate-wide queue; a queue left from
  // another test's fake-async zone would never complete in this one.
  LoginAttemptGuard.resetIsolateStateForTest();
  final auth = FakeLocalAuthClient(authenticateResult: unlock);
  final keys = KeyManager(
    biometric: BiometricService(client: auth),
    storage: InMemoryKeyValueStorage(),
  );
  await keys.storeKeys(
    mnemonic: 'never read by a vote',
    privateKey: seed,
    address: address,
    keyScheme: scheme,
  );
  final api = FakeAdvisoryApi(
    [proposal ?? welcomeProposalJson()],
    eligibility: eligibility,
    actionStatus: actionStatus,
    actionBody: actionBody,
    actionTransportError: actionTransportError,
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
      child: MaterialApp(home: ProposalDetailScreen(proposalId: proposalId)),
    ),
  );
}

Future<void> tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> openSheet(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('eligible: For/Against, then the sheet says exactly what is '
      'signed, one unlock, the exact body, "Sent", refresh', (tester) async {
    await tall(tester);
    final s = await setup();
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();

    expect(find.text('Vote For'), findsOneWidget);
    expect(find.text('Vote Against'), findsOneWidget);
    expect(find.textContaining('no recovery words needed'), findsOneWidget);
    expect(s.unlocks, 0);

    await openSheet(tester, 'advisory-vote-for');
    final sheet = find.byKey(const Key('advisory-vote-sheet'));
    expect(sheet, findsOneWidget);
    String sel(String k) =>
        tester.widget<SelectableText>(find.byKey(Key(k))).data!;
    expect(sel('sheet-title'), 'Welcome to Wrfcoin Governance');
    expect(sel('sheet-choice'), 'For');
    expect(sel('sheet-wallet'), address);
    expect(find.text('WRFCoin testnet (chain 888)'), findsOneWidget);
    expect(find.textContaining('recovery words are never needed'), findsOne);
    // Nothing is unlocked or sent by opening the sheet.
    expect(s.unlocks, 0);
    expect(s.posts, isEmpty);

    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();

    expect(s.unlocks, 1);
    expect(s.posts, hasLength(1));
    final body = s.api.posted.single;
    expect(body['action'], {
      'vote': {'proposal_id': id, 'approve': true},
    });
    expect(body['nonce'], 7);
    expect(body['account'], hasLength(20));
    expect(find.text(advisoryPendingNote), findsOneWidget);
    expect(find.textContaining('77 seconds'), findsOneWidget);
    expect(find.text('Vote For'), findsNothing);
    // Refreshed at once: the proposal and the eligibility are read again.
    final detailReads = s.api.calls
        .where((c) => c == 'GET /api/governance/advisory/proposals/$id')
        .length;
    expect(detailReads, 2);
    expect(s.api.calls.where((c) => c == eligibilityCall), hasLength(3));

    // About a block later it reads again; once counted it says so.
    s.api.eligibility = votedJson('for');
    await tester.pump(const Duration(seconds: 91));
    await tester.pumpAndSettle();
    expect(s.api.calls.where((c) => c == eligibilityCall), hasLength(4));
    expect(find.text('This wallet already voted for.'), findsOneWidget);
  });

  testWidgets('answer lost after sending: "may still count", no vote '
      'buttons, never "failed", then the chain read says how it voted', (
    tester,
  ) async {
    await tall(tester);
    final s = await setup(
      actionTransportError: DioExceptionType.receiveTimeout,
    );
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    await openSheet(tester, 'advisory-vote-for');
    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();

    expect(s.posts, hasLength(1));
    expect(find.byKey(const Key('advisory-vote-unknown')), findsOneWidget);
    expect(find.text(advisoryVoteUnknownNote), findsOneWidget);
    expect(find.textContaining('failed'), findsNothing);
    expect(find.byKey(const Key('advisory-vote-error')), findsNothing);
    expect(find.text('Vote For'), findsNothing);

    // The chain read is the answer: it did count.
    s.api.eligibility = votedJson('for');
    await tester.pump(const Duration(seconds: 91));
    await tester.pumpAndSettle();
    expect(find.text('This wallet already voted for.'), findsOneWidget);
    expect(find.byKey(const Key('advisory-vote-unknown')), findsNothing);
  });

  testWidgets('the signed body matches the core4 vector for the same inputs', (
    tester,
  ) async {
    // Same wallet, proposal, choice and nonce as core4's ed25519_vote case.
    await tall(tester);
    final vectors = jsonDecode(
      File('test/services/crypto/advisory_governance_vectors.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final c = (vectors['cases'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['name'] == 'ed25519_vote');
    final s = await setup(
      proposal: {...welcomeProposalJson(), 'id': 'adv-bb41213ed8b391ca'},
      proposalId: 'adv-bb41213ed8b391ca',
    );
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    await openSheet(tester, 'advisory-vote-against');
    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();
    expect(jsonEncode(s.api.posted.single), c['data']);
  });

  testWidgets('cancel on the sheet: no unlock, nothing sent', (tester) async {
    await tall(tester);
    final s = await setup();
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    await openSheet(tester, 'advisory-vote-against');
    expect(find.text('Against'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sheet-cancel')));
    await tester.pumpAndSettle();
    expect(s.unlocks, 0);
    expect(s.posts, isEmpty);
    expect(find.text('Vote Against'), findsOneWidget);
  });

  testWidgets('the unlock gate is required: refused unlock sends nothing', (
    tester,
  ) async {
    await tall(tester);
    final s = await setup(unlock: false);
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    await openSheet(tester, 'advisory-vote-for');
    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();
    expect(s.unlocks, 1);
    expect(s.posts, isEmpty);
    expect(find.text('Unlock cancelled. Nothing was sent.'), findsOneWidget);
    expect(find.text('Vote For'), findsOneWidget);
  });

  testWidgets('not eligible: says why, no vote buttons', (tester) async {
    await tall(tester);
    final s = await setup(eligibility: notEligibleJson());
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    expect(
      find.text(
        "This wallet can't vote on this proposal: it held less than 1 WRF "
        'when the proposal was created (block 27028). It can vote on '
        'proposals created from now on, while it holds 1 WRF or more.',
      ),
      findsOneWidget,
    );
    expect(find.text('Vote For'), findsNothing);
    expect(find.text('Vote Against'), findsNothing);
  });

  testWidgets('already voted: says which way, no vote buttons', (tester) async {
    await tall(tester);
    final s = await setup(eligibility: votedJson('against'));
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    expect(find.text('This wallet already voted against.'), findsOneWidget);
    expect(find.text('Vote For'), findsNothing);
  });

  testWidgets('voting closed (deadline passed, not yet decided)', (
    tester,
  ) async {
    await tall(tester);
    final s = await setup(eligibility: closedJson());
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    expect(find.text('Voting on this proposal has closed.'), findsOneWidget);
    expect(find.text('Vote For'), findsNothing);
  });

  testWidgets('decided proposal: no vote panel, no eligibility read', (
    tester,
  ) async {
    await tall(tester);
    final s = await setup(
      proposal: {
        ...welcomeProposalJson(),
        'status': 'passed',
        'finalized_at_block': 28149,
      },
    );
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('advisory-vote-panel')), findsNothing);
    expect(s.api.calls.where((c) => c.contains('eligibility')), isEmpty);
  });

  testWidgets('relay refusal shows in plain words (rate limited)', (
    tester,
  ) async {
    await tall(tester);
    final s = await setup(
      actionStatus: 429,
      actionBody: errorBody('RATE_LIMITED', 'Too many requests'),
    );
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    await openSheet(tester, 'advisory-vote-for');
    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.text('Too many tries. Wait a few minutes and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('older wallet type: "can\'t vote yet", no website link', (
    tester,
  ) async {
    await tall(tester);
    final s = await setup(scheme: KeyManager.legacyKeyScheme);
    await tester.pumpWidget(s.widget);
    await tester.pumpAndSettle();
    expect(find.text("This wallet type can't vote yet."), findsOneWidget);
    expect(find.textContaining('wrfcoin.com'), findsNothing);
    expect(find.text('Vote For'), findsNothing);
    expect(s.api.calls.where((c) => c.contains('eligibility')), isEmpty);
  });
}
