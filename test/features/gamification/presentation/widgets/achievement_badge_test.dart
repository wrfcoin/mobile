import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/gamification/data/models/achievement_model.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/widgets/achievement_badge.dart';

void main() {
  const earnedAchievement = AchievementModel(
    id: '1',
    name: 'Bronze Tier',
    description: 'First step',
    tier: 'bronze',
    progress: 1,
    earned: true,
  );

  const unearnedAchievement = AchievementModel(
    id: '2',
    name: 'Diamond Tier',
    description: 'Hard mode',
    tier: 'diamond',
    progress: 0.4,
    earned: false,
  );

  testWidgets('shows earned badge with check overlay', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AchievementBadge(achievement: earnedAchievement),
        ),
      ),
    );

    expect(find.text('BRONZE'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('shows locked state for unearned badge', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AchievementBadge(achievement: unearnedAchievement),
        ),
      ),
    );

    expect(find.text('40%'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('isNew: true — renders without overflow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 140,
            child: AchievementBadge(
              achievement: earnedAchievement,
              isNew: true,
            ),
          ),
        ),
      ),
    );

    // Pump through the scale-in (400ms) + shimmer timer (600ms after animation).
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    // Drain the 600ms Future.delayed shimmer timer so no pending timers remain.
    await tester.pump(const Duration(milliseconds: 700));
    // No overflow or render exceptions means the test passes.
    expect(tester.takeException(), isNull);
  });

  testWidgets('isNew: false — renders without animation in test environment',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 140,
            child: AchievementBadge(
              achievement: earnedAchievement,
              isNew: false,
            ),
          ),
        ),
      ),
    );

    // Single pump — no animation queued.
    await tester.pump();
    expect(find.text('BRONZE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RepaintBoundary is present in the widget tree', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AchievementBadge(achievement: earnedAchievement),
        ),
      ),
    );

    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets('Semantics label describes earned achievement', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AchievementBadge(achievement: earnedAchievement),
        ),
      ),
    );

    final semanticsNode = tester.getSemantics(find.byType(AchievementBadge));
    expect(semanticsNode.label, contains('Bronze Tier'));
    expect(semanticsNode.label, contains('earned'));
  });
}
