import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:wrfcoin_mobile/features/governance/data/models/advisory_vote.dart';
import 'package:wrfcoin_mobile/features/governance/data/repositories/governance_repository_impl.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/auth/login_attempt_guard.dart';
import 'package:wrfcoin_mobile/services/crypto/advisory_action_signing.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';
import 'package:wrfcoin_mobile/services/crypto/transfer_signing_domain.dart';

import '../../../test_helpers/fakes.dart';
import '../fixtures/advisory_api.dart';

// The website/core4 vector wallet (seed 0x42 x 32) and its vote case:
// adv-bb41213ed8b391ca, against, nonce 7 (advisory_governance_vectors.json).
const seed = '4242424242424242424242424242424242424242424242424242424242424242';
const address = '0xa307fb31c7585b6ccb5dc3ddc844e22b14b7aa0d';
const proposalId = 'adv-bb41213ed8b391ca';

class CountingStorage extends InMemoryKeyValueStorage {
  final Map<String, int> reads = <String, int>{};
  @override
  Future<String?> read({required String key}) {
    reads[key] = (reads[key] ?? 0) + 1;
    return super.read(key: key);
  }
}

class Harness {
  Harness(this.api, this.repo, this.auth, this.storage);
  final FakeAdvisoryApi api;
  final GovernanceRepository repo;
  final FakeLocalAuthClient auth;
  final CountingStorage storage;

  int get unlockPrompts => auth.authenticateBiometricOnlyCalls.length;
  Iterable<String> get posts => api.calls.where((c) => c.startsWith('POST'));
}

Future<Harness> harness({
  Map<String, dynamic>? eligibility,
  int actionStatus = 202,
  Object? actionBody,
  DioExceptionType? actionTransportError,
  bool unlock = true,
  String scheme = KeyManager.canonicalKeyScheme,
  bool wallet = true,
  int nonce = 3,
  String? balance = '10900000000',
}) async {
  LoginAttemptGuard.resetIsolateStateForTest();
  final storage = CountingStorage();
  final auth = FakeLocalAuthClient(authenticateResult: unlock);
  final keys = KeyManager(
    biometric: BiometricService(client: auth),
    storage: storage,
  );
  if (wallet) {
    await keys.storeKeys(
      mnemonic: 'never read by a vote',
      privateKey: seed,
      address: address,
      keyScheme: scheme,
    );
  }
  // storeKeys reads the old slots (to put them back if the save fails);
  // count only what the vote or proposal reads.
  storage.reads.clear();
  final api = FakeAdvisoryApi(
    const [],
    eligibility: eligibility,
    actionStatus: actionStatus,
    actionBody: actionBody,
    actionTransportError: actionTransportError,
    nonce: nonce,
    balance: balance,
  );
  final repo = GovernanceRepository(
    api.dio(),
    advisorySigner: AdvisoryActionSigner(
      keyManager: keys,
      domain: const TransferSigningDomain(chainId: '888', networkId: 'testnet'),
      isForeground: () => true,
    ),
  );
  return Harness(api, repo, auth, storage);
}

AdvisoryRefusal refusalOf(Either<AdvisoryRefusal, AdvisorySubmitted> r) =>
    r.fold((l) => l, (_) => fail('expected a refusal'));

void main() {
  final vectors = jsonDecode(
    File('test/services/crypto/advisory_governance_vectors.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final voteCase = (vectors['cases'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((c) => c['name'] == 'ed25519_vote');
  final proposeCase = (vectors['cases'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((c) => c['name'] == 'ed25519_propose');

  test('success: eligibility, one unlock, then the exact core4 body', () async {
    final h = await harness();
    final r = await h.repo.voteAdvisory(proposalId: proposalId, approve: false);

    final sent = r.getOrElse((l) => fail('refused: ${l.message}'));
    expect(sent.nonce, 7);
    expect(sent.txId, 'ab' * 32);
    expect(h.api.calls, [
      'GET /api/governance/advisory/proposals/$proposalId/eligibility'
          '?address=$address',
      'POST /api/governance/advisory/actions',
    ]);
    expect(h.unlockPrompts, 1);
    // Byte-identical to the JSON core4 serializes for the same inputs.
    expect(jsonEncode(h.api.posted.single), voteCase['data']);
    // The edge admits exactly this Content-Type.
    expect(h.api.postedContentTypes.single, 'application/json');
    // The recovery phrase is never read.
    expect(h.storage.reads['wrf_mnemonic'], isNull);
  });

  test('unlock refused: nothing is sent', () async {
    final h = await harness(unlock: false);
    final r = await h.repo.voteAdvisory(proposalId: proposalId, approve: true);
    expect(refusalOf(r).kind, AdvisoryRefusalKind.unlockCancelled);
    expect(refusalOf(r).message, 'Unlock cancelled. Nothing was sent.');
    expect(h.unlockPrompts, 1);
    expect(h.posts, isEmpty);
  });

  group('eligibility refusals: said plainly, no unlock, nothing sent', () {
    final cases = <String, (Map<String, dynamic>, AdvisoryRefusalKind, String)>{
      'not eligible': (
        notEligibleJson(),
        AdvisoryRefusalKind.notEligible,
        "This wallet can't vote on this one: it held under 1 WRF when the "
            'proposal was made.',
      ),
      'already voted': (
        votedJson('for'),
        AdvisoryRefusalKind.alreadyVoted,
        'This wallet already voted for.',
      ),
      'closed': (
        closedJson(),
        AdvisoryRefusalKind.votingClosed,
        'Voting on this proposal has closed.',
      ),
      'no account on chain (no nonce)': (
        {...eligibleJson(nextNonce: null), 'canVote': true},
        AdvisoryRefusalKind.other,
        "This wallet can't vote on this one.",
      ),
    };
    cases.forEach((name, c) {
      test(name, () async {
        final h = await harness(eligibility: c.$1);
        final r = await h.repo.voteAdvisory(
          proposalId: proposalId,
          approve: true,
        );
        expect(refusalOf(r).kind, c.$2);
        expect(refusalOf(r).message, c.$3);
        expect(h.unlockPrompts, 0);
        expect(h.posts, isEmpty);
      });
    });
  });

  group('relay and node refusals in plain words', () {
    final cases = <String, (int, Object?, AdvisoryRefusalKind, String)>{
      'rate limited (IP or account limiter)': (
        429,
        errorBody('RATE_LIMITED', 'Too many requests, please try again later'),
        AdvisoryRefusalKind.rateLimited,
        'Too many tries. Wait a few minutes and try again.',
      ),
      'node: already voted': (
        422,
        errorBody(
          'ADVISORY_GOVERNANCE_REFUSED',
          'SP_ADVISORY_GOVERNANCE_REFUSED: wallet already voted',
        ),
        AdvisoryRefusalKind.alreadyVoted,
        'This wallet already voted on this proposal.',
      ),
      'node: not eligible': (
        422,
        errorBody(
          'ADVISORY_GOVERNANCE_REFUSED',
          'governance: SP_ADVISORY_GOVERNANCE_REFUSED: wallet held under 1 '
              'WRF spendable when the proposal was created',
        ),
        AdvisoryRefusalKind.notEligible,
        "This wallet can't vote on this one: it held under 1 WRF when the "
            'proposal was made.',
      ),
      'node: voting closed': (
        422,
        errorBody(
          'ADVISORY_GOVERNANCE_REFUSED',
          'SP_ADVISORY_GOVERNANCE_REFUSED: voting period has ended',
        ),
        AdvisoryRefusalKind.votingClosed,
        'Voting on this proposal has closed.',
      ),
      'node: feature not active': (
        503,
        errorBody(
          'FEATURE_NOT_ACTIVE',
          'advisory_governance is not active at the next height',
        ),
        AdvisoryRefusalKind.notActive,
        'Advisory voting is not on in the network yet.',
      ),
      'relay switched off (404)': (
        404,
        errorBody('NOT_FOUND', 'Not found'),
        AdvisoryRefusalKind.relayOff,
        'Voting is switched off on the server right now. Nothing was sent.',
      ),
      'node: other refusal': (
        422,
        errorBody(
          'ADVISORY_GOVERNANCE_REFUSED',
          'SP_ADVISORY_GOVERNANCE_REFUSED: unknown account',
        ),
        AdvisoryRefusalKind.refused,
        'The network refused it: unknown account',
      ),
      'mempool refusal': (
        422,
        errorBody('MEMPOOL_REJECTED', 'duplicate transaction'),
        AdvisoryRefusalKind.refused,
        'The network refused it: duplicate transaction',
      ),
      'relay validation': (
        400,
        errorBody('VALIDATION_ERROR', 'account must be a 20-byte array'),
        AdvisoryRefusalKind.other,
        'account must be a 20-byte array',
      ),
      // The relay passed it on and lost the node's answer: the vote may
      // still count, so never "failed, try again".
      'upstream failure: outcome unknown': (
        502,
        errorBody('UPSTREAM_ERROR', 'Upstream node request failed'),
        AdvisoryRefusalKind.unknown,
        advisoryVoteUnknownNote,
      ),
      'edge gateway timeout: outcome unknown': (
        504,
        '<html>gateway timeout</html>',
        AdvisoryRefusalKind.unknown,
        advisoryVoteUnknownNote,
      ),
    };
    cases.forEach((name, c) {
      test(name, () async {
        final h = await harness(actionStatus: c.$1, actionBody: c.$2);
        final r = await h.repo.voteAdvisory(
          proposalId: proposalId,
          approve: true,
        );
        expect(refusalOf(r).kind, c.$3);
        expect(refusalOf(r).message, c.$4);
        // Signed and sent exactly once; never retried.
        expect(h.posts, hasLength(1));
        expect(h.unlockPrompts, 1);
      });
    });
  });

  group('transport errors on the signed POST', () {
    final cases = <DioExceptionType, (AdvisoryRefusalKind, String)>{
      // Never connected: nothing left the phone.
      DioExceptionType.connectionError: (
        AdvisoryRefusalKind.network,
        'Could not reach the network. Nothing was sent. Check your '
            'connection and try again.',
      ),
      DioExceptionType.connectionTimeout: (
        AdvisoryRefusalKind.network,
        'Could not reach the network. Nothing was sent. Check your '
            'connection and try again.',
      ),
      // Connected and sent (or sending): the answer is lost, not "failed".
      DioExceptionType.sendTimeout: (
        AdvisoryRefusalKind.unknown,
        advisoryVoteUnknownNote,
      ),
      DioExceptionType.receiveTimeout: (
        AdvisoryRefusalKind.unknown,
        advisoryVoteUnknownNote,
      ),
      DioExceptionType.unknown: (
        AdvisoryRefusalKind.unknown,
        advisoryVoteUnknownNote,
      ),
    };
    cases.forEach((type, c) {
      test('$type', () async {
        final h = await harness(actionTransportError: type);
        final r = await h.repo.voteAdvisory(
          proposalId: proposalId,
          approve: true,
        );
        expect(refusalOf(r).kind, c.$1);
        expect(refusalOf(r).message, c.$2);
        expect(refusalOf(r).message, isNot(contains('failed')));
        expect(h.posts, hasLength(1));
      });
    });

    test('propose: a lost answer is unknown, with propose wording', () async {
      final h = await harness(
        actionTransportError: DioExceptionType.receiveTimeout,
      );
      final r = await h.repo.proposeAdvisory(
        title: 'Welcome',
        summary: 'Line one.',
      );
      expect(refusalOf(r).kind, AdvisoryRefusalKind.unknown);
      expect(refusalOf(r).message, advisoryProposeUnknownNote);
    });
  });

  test('older receive-only wallet: "can\'t vote yet", no network', () async {
    final h = await harness(scheme: KeyManager.legacyKeyScheme);
    final r = await h.repo.voteAdvisory(proposalId: proposalId, approve: true);
    expect(refusalOf(r).kind, AdvisoryRefusalKind.cantSign);
    expect(refusalOf(r).message, "This wallet type can't vote yet.");
    expect(h.api.calls, isEmpty);
    expect(h.unlockPrompts, 0);
  });

  test('no wallet in the app: says so, no network', () async {
    final h = await harness(wallet: false);
    final r = await h.repo.voteAdvisory(proposalId: proposalId, approve: true);
    expect(refusalOf(r).kind, AdvisoryRefusalKind.noWallet);
    expect(h.api.calls, isEmpty);
  });

  test(
    'eligibility read sends the lowercase address the edge admits',
    () async {
      final h = await harness();
      final r = await h.repo.getAdvisoryEligibility(
        proposalId,
        address.toUpperCase().replaceFirst('0X', '0x'),
      );
      expect(r.isRight(), isTrue);
      expect(h.api.calls.single, endsWith('?address=$address'));
    },
  );

  group('propose', () {
    test('success: balance, nonce, one unlock, the exact core4 body', () async {
      final h = await harness(nonce: 0);
      final r = await h.repo.proposeAdvisory(
        title: 'Welcome, café 🌧',
        summary: 'Line one.\nLine two.',
      );
      final sent = r.getOrElse((l) => fail('refused: ${l.message}'));
      expect(sent.nonce, 0);
      expect(sent.proposalId, 'adv-bb41213ed8b391ca');
      expect(h.api.calls, [
        'GET /api/public/balance/$address',
        'GET /api/governance/advisory/accounts/$address/nonce',
        'POST /api/governance/advisory/actions',
      ]);
      expect(h.unlockPrompts, 1);
      // Byte-identical to core4's serde JSON (vector ed25519_propose).
      expect(jsonEncode(h.api.posted.single), proposeCase['data']);
      expect(h.api.postedContentTypes.single, 'application/json');
      expect(h.storage.reads['wrf_mnemonic'], isNull);
    });

    test('under 1 WRF: refused before the unlock, nothing sent', () async {
      final h = await harness(balance: '99999999');
      final r = await h.repo.proposeAdvisory(title: 'T', summary: 'S');
      expect(refusalOf(r).kind, AdvisoryRefusalKind.insufficientBalance);
      expect(
        refusalOf(r).message,
        'This wallet has under 1 WRF it can spend. Proposing holds 1 WRF, so '
        "it can't propose yet. Nothing was sent.",
      );
      expect(h.unlockPrompts, 0);
      expect(h.posts, isEmpty);
    });

    test('exactly 1 WRF is enough (the advisory tx pays no fee)', () async {
      final h = await harness(balance: '100000000');
      final r = await h.repo.proposeAdvisory(title: 'T', summary: 'S');
      expect(r.isRight(), isTrue);
    });

    test('balance read switched off: the node decides', () async {
      final h = await harness(balance: null);
      final r = await h.repo.proposeAdvisory(title: 'T', summary: 'S');
      expect(r.isRight(), isTrue);
      expect(h.posts, hasLength(1));
    });

    test('unlock refused: nothing is sent', () async {
      final h = await harness(unlock: false);
      final r = await h.repo.proposeAdvisory(title: 'T', summary: 'S');
      expect(refusalOf(r).kind, AdvisoryRefusalKind.unlockCancelled);
      expect(h.posts, isEmpty);
    });

    final textCases = <String, (String, String, String)>{
      'empty title': ('  ', 'S', 'The title is empty.'),
      'title over 160 bytes': (
        'é' * 81,
        'S',
        'The title is 162 bytes; the limit is 160.',
      ),
      'two-line title': ('a\nb', 'S', 'The title must be one line.'),
      'summary over 1024 bytes': (
        'T',
        'x' * 1025,
        'The summary is 1025 bytes; the limit is 1024.',
      ),
      'bidi override': (
        'T',
        'a\u202Eb',
        'The summary has a character that is not allowed (U+202E).',
      ),
      'control character': (
        'a\tb',
        'S',
        'The title has a character that is not allowed (U+0009).',
      ),
    };
    textCases.forEach((name, c) {
      test('text rule: $name (website wording), no network', () async {
        final h = await harness();
        final r = await h.repo.proposeAdvisory(title: c.$1, summary: c.$2);
        expect(refusalOf(r).kind, AdvisoryRefusalKind.invalidText);
        expect(refusalOf(r).message, c.$3);
        expect(h.api.calls, isEmpty);
      });
    });

    test('exactly 160-byte title and 1024-byte summary are allowed', () {
      expect(advisoryTextProblem(AdvisoryTextField.title, 'a' * 160), isNull);
      expect(
        advisoryTextProblem(AdvisoryTextField.summary, 'a\n' * 512),
        isNull,
      );
    });

    final relayCases = <String, (int, Object?, AdvisoryRefusalKind, String)>{
      'already has an open proposal': (
        422,
        errorBody(
          'ADVISORY_GOVERNANCE_REFUSED',
          'SP_ADVISORY_GOVERNANCE_REFUSED: this wallet already has an active '
              'proposal',
        ),
        AdvisoryRefusalKind.activeProposal,
        'This wallet already has a proposal open. It can propose again once '
            'that one is decided.',
      ),
      'chain full': (
        422,
        errorBody(
          'ADVISORY_GOVERNANCE_REFUSED',
          'SP_ADVISORY_GOVERNANCE_REFUSED: the chain already has the maximum '
              'number of active proposals',
        ),
        AdvisoryRefusalKind.tooManyProposals,
        'The network already has the most open proposals it allows. Try '
            'again when one is decided.',
      ),
      'node: insufficient spendable balance': (
        422,
        errorBody(
          'ADVISORY_GOVERNANCE_REFUSED',
          'Insufficient spendable balance',
        ),
        AdvisoryRefusalKind.insufficientBalance,
        'This wallet has under 1 WRF it can spend. Proposing holds 1 WRF, so '
            "it can't propose yet. Nothing was sent.",
      ),
      'security key': (
        422,
        errorBody(
          'ADVISORY_GOVERNANCE_REFUSED',
          'SP_ADVISORY_GOVERNANCE_REFUSED: accounts with a security key '
              'cannot pay a proposal deposit yet',
        ),
        AdvisoryRefusalKind.depositBlocked,
        "This wallet's spending guard (security key or send allowlist) stops "
            'it paying the proposal deposit.',
      ),
      'rate limited': (
        429,
        errorBody('RATE_LIMITED', 'Too many requests, please try again later'),
        AdvisoryRefusalKind.rateLimited,
        'Too many tries. Wait a few minutes and try again.',
      ),
    };
    relayCases.forEach((name, c) {
      test('relay refusal: $name', () async {
        final h = await harness(actionStatus: c.$1, actionBody: c.$2);
        final r = await h.repo.proposeAdvisory(title: 'T', summary: 'S');
        expect(refusalOf(r).kind, c.$3);
        expect(refusalOf(r).message, c.$4);
        expect(h.posts, hasLength(1));
      });
    });

    test('older wallet type: can\'t propose yet, no network', () async {
      final h = await harness(scheme: KeyManager.legacyKeyScheme);
      final r = await h.repo.proposeAdvisory(title: 'T', summary: 'S');
      expect(refusalOf(r).message, "This wallet type can't propose yet.");
      expect(h.api.calls, isEmpty);
    });
  });
}
