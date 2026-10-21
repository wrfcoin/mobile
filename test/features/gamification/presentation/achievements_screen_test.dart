import 'package:dio/dio.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/providers/role_earnings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/achievement_model.dart';
import 'package:wrfcoin_mobile/features/gamification/data/repositories/gamification_repository_impl.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/achievements_screen.dart';

void main() {
  group('AchievementModel unlock rule', () {
    test('progress >= 1.0 with earned: true is unlocked', () {
      const a = AchievementModel(
        id: 'a1',
        name: 'Bronze',
        description: 'desc',
        tier: 'bronze',
        progress: 1.0,
        earned: true,
      );
      expect(a.earned, isTrue);
      expect(a.progress, equals(1.0));
    });

    test('progress < 1.0 with earned: false is locked', () {
      const a = AchievementModel(
        id: 'a2',
        name: 'Diamond',
        description: 'desc',
        tier: 'diamond',
        progress: 0.4,
        earned: false,
      );
      expect(a.earned, isFalse);
      expect(a.progress, lessThan(1.0));
    });

    test('earned: true regardless of progress is treated as earned', () {
      const a = AchievementModel(
        id: 'a3',
        name: 'Silver',
        description: 'desc',
        tier: 'silver',
        progress: 0.5,
        earned: true,
      );
      expect(a.earned, isTrue);
    });
  });

  test('Profile defaults on; saved opt-out survives restart', () async {
    expect(const FeatureFlags().enableAchievementsUi, isTrue);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer container() => ProviderContainer(
      overrides: [
        earningsReadProvider.overrideWith((ref) async => false),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    final first = container();
    expect(first.read(featureFlagsProvider).enableAchievementsUi, isTrue);
    await first
        .read(featureFlagsProvider.notifier)
        .setAchievementsUi(enabled: false);
    first.dispose();
    final restarted = container();
    expect(restarted.read(featureFlagsProvider).enableAchievementsUi, isFalse);
    restarted.dispose();
  });

  testWidgets(
    'unwired achievements and NFTs make no unsupported request or claim',
    (tester) async {
      SharedPreferences.setMockInitialValues({'ff_enableNftPortfolio': true});
      final prefs = await SharedPreferences.getInstance();
      final paths = <String>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            paths.add(o.path);
            h.resolve(
              Response(
                requestOptions: o,
                data: {
                  'success': false,
                  'unavailable': ['earnings'],
                  'entries': [],
                },
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            earningsReadProvider.overrideWith((ref) async => false),
            sharedPreferencesProvider.overrideWithValue(prefs),
            gamificationRepositoryProvider.overrideWithValue(
              GamificationRepository(dio),
            ),
          ],
          child: const MaterialApp(home: AchievementsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Achievements are not available yet.'),
        findsOneWidget,
      );
      expect(find.text('Claim\nReward', skipOffstage: false), findsNothing);
      expect(find.text('No Achievements Yet'), findsNothing);
      expect(paths.every((p) => p == '/weather/leaderboard'), isTrue);
      await tester.tap(find.text('Leaderboard'));
      await tester.pumpAndSettle();
      expect(find.text('Earnings unavailable right now'), findsOneWidget);
      expect(paths, ['/weather/leaderboard']);
    },
  );
}
