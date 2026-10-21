import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'leaderboard_screen.dart';
import '../widgets/role_earnings_board.dart';

class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          Semantics(
            button: true,
            label: 'Open settings',
            child: IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.tune),
              onPressed: () => context.push('/profile/settings'),
            ),
          ),
          Semantics(
            button: true,
            label: 'Open data desert map',
            child: IconButton(
              tooltip: 'Data desert map',
              icon: const Icon(Icons.map),
              onPressed: () => context.push('/profile/deserts'),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Achievements'),
            Tab(text: 'Leaderboard'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          SingleChildScrollView(
            child: Column(
              children: [
                OwnRoleEarningsSummary(),
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Achievements are not available yet.\n'
                    'Badges and reward claims will appear when the service is ready.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          LeaderboardScreen(embedded: true),
        ],
      ),
    );
  }
}
