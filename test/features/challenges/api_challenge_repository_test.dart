import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/constants/api_constants.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/challenges/data/models/challenge_model.dart';
import 'package:wrfcoin_mobile/features/challenges/data/repositories/challenge_repository.dart';

const _you = '0x1234567890abcdef1234567890abcdef12345678';
const _friend = '0xb2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2';

/// The exact shape backend#249 challenge-routes.ts answers.
Map<String, dynamic> _challenge({String status = 'live'}) => {
  'id': '6f1d2c4e-8a8b-4c1e-9d6a-1f2e3d4c5b6a',
  'title': 'Coast race',
  'description': 'Who logs more',
  'format': 'headToHead',
  'status': status,
  'inviteCode': 'RAIN-7K2Q',
  'targetScore': 50,
  'startsAt': '2026-11-02T00:00:00.000Z',
  'endsAt': '2026-11-09T00:00:00.000Z',
  'completedAt': null,
  'lastUpdatedAt': '2026-11-02T12:00:00.000Z',
  'metricLabel': 'readings on chain',
  'scoring': {'source': 'chain', 'note': 'x', 'countedAt': null},
  'participants': [
    {
      'id': _friend,
      'name': 'Collector B2B2',
      'score': 7,
      'teamName': '',
      'subtitle': 'Challenge host',
      'stations': 1,
    },
    {
      'id': _you.toUpperCase().replaceFirst('0X', '0x'),
      'name': 'Collector 5678',
      'score': 3,
      'teamName': '',
      'subtitle': 'Joined by invite code',
      'stations': 0,
    },
  ],
};

class _Server implements HttpClientAdapter {
  _Server(this.answer);
  final ResponseBody Function(RequestOptions options) answer;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return answer(options);
  }
}

ResponseBody _json(Object data, int status) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

(ApiChallengeRepository, _Server) _repo(
  ResponseBody Function(RequestOptions) answer,
) {
  final server = _Server(answer);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'))
    ..httpClientAdapter = server;
  return (ApiChallengeRepository(dio), server);
}

void main() {
  test(
    'reads the server board as the phone model and marks the wallet',
    () async {
      final (repo, server) = _repo(
        (_) => _json({
          'challenges': [_challenge()],
        }, 200),
      );
      final result = await repo.getChallenges(userId: _you, displayName: 'x');
      final list = result.getOrElse((_) => fail('expected challenges'));
      expect(server.requests.single.path, ApiConstants.challenges);
      expect(server.requests.single.method, 'GET');
      final c = list.single;
      expect(c.status, ChallengeStatus.live);
      expect(c.inviteCode, 'RAIN-7K2Q');
      expect(c.metricLabel, 'readings on chain');
      expect(c.currentUserParticipant?.score, 3);
      expect(
        c.currentUserParticipant?.subtitle,
        contains('no station linked to this wallet'),
      );
      expect(c.topScore, 7);
    },
  );

  test(
    'create sends the form fields only, never a user id or a name',
    () async {
      final (repo, server) = _repo(
        (_) => _json({
          'challenges': [_challenge(status: 'pending')],
        }, 201),
      );
      await repo.createChallenge(
        userId: _you,
        displayName: 'Collector 5678',
        input: const CreateChallengeInput(
          title: ' Fog Chase ',
          description: 'Catch 25 coastal readings first.',
          format: ChallengeFormat.team,
          targetScore: 25,
          duration: Duration(days: 3),
        ),
      );
      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.path, ApiConstants.challenges);
      expect(request.data, {
        'title': 'Fog Chase',
        'description': 'Catch 25 coastal readings first.',
        'format': 'team',
        'targetScore': 25,
        'durationHours': 72,
      });
    },
  );

  test(
    'join uppercases the code; refusals and a switched-off server read plainly',
    () async {
      final (repo, server) = _repo(
        (_) => _json({
          'success': false,
          'error': {'code': 'CHALLENGE_FULL', 'message': 'x'},
        }, 409),
      );
      final full = await repo.joinChallengeByReferralCode(
        userId: _you,
        displayName: 'x',
        referralCode: ' rain-7k2q ',
      );
      expect(server.requests.single.data, {'inviteCode': 'RAIN-7K2Q'});
      expect(
        full.getLeft().toNullable()?.message,
        'This challenge is already full.',
      );

      final (off, _) = _repo((_) => _json({'error': 'Not found'}, 404));
      final missing = await off.getChallenges(userId: _you, displayName: 'x');
      expect(missing.getLeft().toNullable(), isA<NotAvailableFailure>());

      final (signedOut, _) = _repo(
        (_) => _json({'error': 'Bearer Token Required'}, 401),
      );
      final auth = await signedOut.getChallenges(
        userId: _you,
        displayName: 'x',
      );
      expect(auth.getLeft().toNullable(), isA<AuthFailure>());
    },
  );

  test(
    'a new reading asks the server for counts; the local delta is never sent',
    () async {
      final (repo, server) = _repo(
        (_) => _json({
          'challenges': [_challenge()],
        }, 200),
      );
      await repo.registerCollection(userId: _you, delta: 5);
      expect(server.requests.single.path, ApiConstants.challengesSync);
      expect(server.requests.single.data, isEmpty);
    },
  );

  test(
    'the flag picks the service: off is the unavailable repository',
    () async {
      SharedPreferences.setMockInitialValues({
        'ff_enableFriendChallenges': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(container.read(challengeCapabilityProvider).available, isFalse);
      expect(
        container.read(challengeRepositoryProvider),
        isA<UnavailableChallengeRepository>(),
      );
      await container
          .read(featureFlagsProvider.notifier)
          .setFriendChallenges(enabled: true);
      expect(container.read(challengeCapabilityProvider).available, isTrue);
    },
  );

  test('the flag is on by default: the backend service is used', () async {
    expect(const FeatureFlags().enableFriendChallenges, isTrue);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(featureFlagsProvider).enableFriendChallenges, isTrue);
    expect(container.read(challengeCapabilityProvider).available, isTrue);
  });
}
