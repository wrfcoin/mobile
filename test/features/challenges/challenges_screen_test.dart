import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/challenges/data/models/challenge_model.dart';
import 'package:wrfcoin_mobile/features/challenges/data/repositories/challenge_repository.dart';
import 'package:wrfcoin_mobile/features/challenges/presentation/providers/challenges_provider.dart';
import 'package:wrfcoin_mobile/features/challenges/presentation/screens/challenges_screen.dart';
import 'package:wrfcoin_mobile/services/auth/biometric_service.dart';
import 'package:wrfcoin_mobile/services/crypto/key_manager.dart';

import '../../test_helpers/fakes.dart';

void main() {
  testWidgets(
    'release route blocks Friend Challenges when its flag is turned off',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/collect/challenges',
        routes: [
          GoRoute(
            path: '/collect/challenges',
            builder: (context, state) => const FriendChallengesRoute(),
          ),
        ],
      );
      addTearDown(router.dispose);

      // The flag is on by default; this checks the turned-off state.
      SharedPreferences.setMockInitialValues({
        'ff_enableFriendChallenges': false,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Friend Challenges unavailable'), findsOneWidget);
      expect(
        find.textContaining('persistent challenge service'),
        findsOneWidget,
      );
      expect(find.text('Live Competitions'), findsNothing);
      expect(find.text('Create or join'), findsNothing);
    },
  );

  testWidgets(
    'injected capability and repository enable canonical challenge events',
    (tester) async {
      final keyStorage = InMemoryKeyValueStorage();
      await keyStorage.write(
        key: 'wrf_address',
        value: '0x1234567890abcdef1234567890abcdef12345678',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            challengeCapabilityProvider.overrideWithValue(
              const ChallengeCapability(
                available: true,
                reason: 'Test repository connected.',
              ),
            ),
            challengeRepositoryProvider.overrideWithValue(
              FakeChallengeRepository(),
            ),
            keyManagerProvider.overrideWithValue(
              KeyManager(
                storage: keyStorage,
                biometric: BiometricService(client: FakeLocalAuthClient()),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const FriendChallengesRoute(),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Friend Challenges'), findsOneWidget);
      expect(find.text('Create or join'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChallengesScreen)),
      );
      await container
          .read(challengesProvider.notifier)
          .createChallenge(
            const CreateChallengeInput(
              title: 'Fog Chase',
              description: 'Catch 25 coastal readings first.',
              format: ChallengeFormat.headToHead,
              targetScore: 25,
              duration: Duration(days: 3),
            ),
          );
      await tester.pumpAndSettle();

      final createdState = container.read(challengesProvider);
      final createdChallenge = createdState.challenges.firstWhere(
        (challenge) => challenge.title == 'Fog Chase',
      );
      expect(createdChallenge.inviteCode, 'TEST-42');

      await container
          .read(challengesProvider.notifier)
          .joinByReferralCode('RADAR-21');
      await tester.pumpAndSettle();

      final joinedChallenge = container
          .read(challengesProvider)
          .challenges
          .firstWhere((challenge) => challenge.title == 'Referral Race');
      expect(
        joinedChallenge.participants.any(
          (participant) => participant.isCurrentUser,
        ),
        isTrue,
      );

      final scoreBefore = joinedChallenge.participants
          .firstWhere((participant) => participant.isCurrentUser)
          .score;
      await container
          .read(challengesProvider.notifier)
          .registerCollectionDelta(2);
      await tester.pumpAndSettle();

      final scoreAfter = container
          .read(challengesProvider)
          .challenges
          .firstWhere((challenge) => challenge.title == 'Referral Race')
          .participants
          .firstWhere((participant) => participant.isCurrentUser)
          .score;
      expect(scoreAfter, greaterThan(scoreBefore));
    },
  );
}
