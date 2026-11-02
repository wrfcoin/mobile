import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_handoff.dart';
import '../time/app_clock.dart';
import '../layout/responsive_layout.dart';
import '../../features/weather/presentation/screens/forecast_dashboard.dart';
import '../../features/weather/presentation/screens/weather_stories_screen.dart';
import '../../features/weather/presentation/screens/weather_map_screen.dart';
import '../../features/weather/presentation/screens/ar_viewer_screen.dart';
import '../../features/weather/presentation/screens/alerts_screen.dart';
import '../../features/weather/presentation/screens/alert_settings_screen.dart';
import '../../features/weather/presentation/screens/forecast_detail_screen.dart';
import '../../features/weather/data/models/forecast_model.dart';
import '../../features/collector/presentation/screens/collector_dashboard.dart';
import '../../features/collector/presentation/screens/collector_validation_screen.dart';
import '../../features/collector/presentation/screens/sensor_settings_screen.dart';
import '../../features/collector/presentation/screens/imagery_upload_screen.dart';
import '../../features/collector/presentation/screens/pws_dashboard_screen.dart';
import '../../features/collector/presentation/screens/station_accept_screen.dart';
import '../../features/collector/presentation/screens/station_profile_screen.dart';
import '../../features/collector/presentation/screens/station_recovery_screen.dart';
import '../../features/collector/presentation/screens/station_security_screen.dart';
import '../../features/collector/presentation/screens/station_transfer_screen.dart';
import '../../features/calibration/presentation/station_calibration_screen.dart';
import '../../features/challenges/presentation/screens/challenges_screen.dart';
import '../../features/duels/presentation/screens/forecast_duel_screen.dart';
import '../../features/duels/presentation/screens/forecast_duels_screen.dart';
import '../../features/competitions/presentation/screens/competitions_screen.dart';
import '../../features/forecast_check/presentation/screens/forecast_check_screen.dart';
import '../../features/notifications/presentation/payout_notifications_screen.dart';
import '../../features/collector/presentation/providers/mobile_station_status_provider.dart';
import '../../features/gamification/presentation/providers/role_earnings_provider.dart';
import '../../features/wallet/presentation/providers/transactions_provider.dart';
import '../../features/wallet/presentation/screens/wallet_screen.dart';
import '../../features/analytics/presentation/screens/analytics_dashboard_screen.dart';
import '../../features/wallet/presentation/screens/send_screen.dart';
import '../../features/wallet/presentation/screens/receive_screen.dart';
import '../../features/wallet/presentation/screens/create_wallet_screen.dart';
import '../../features/wallet/presentation/screens/import_wallet_screen.dart';
import '../../features/carbon_lottery/presentation/screens/carbon_lottery_dashboard_screen.dart';
import '../../features/faucet/presentation/screens/faucet_screen.dart';
import '../../features/explorer/presentation/screens/chain_screen.dart';
import '../../features/network_nodes/presentation/screens/network_nodes_screen.dart';
import '../../features/governance/presentation/screens/proposal_list_screen.dart';
import '../../features/more/presentation/screens/more_screen.dart';
import '../../features/governance/presentation/screens/proposal_detail_screen.dart';
import '../../features/governance/presentation/screens/vote_screen.dart';
import '../../features/governance/data/models/proposal_model.dart';
import '../../features/gamification/presentation/screens/achievements_screen.dart';
import '../../features/gamification/presentation/screens/data_desert_map_screen.dart';
import '../../features/gamification/presentation/screens/leaderboard_screen.dart';
import '../../features/field_diagnostics/presentation/screens/field_mode_screen.dart';
import '../feature_flags/build_flags.dart';
import '../feature_flags/feature_flags.dart';
import '../../features/onboarding/presentation/providers/onboarding_controller.dart';
import '../../features/onboarding/presentation/providers/welcome_controller.dart';
import '../../features/onboarding/presentation/screens/onboarding_tour_screen.dart';
import '../../features/onboarding/presentation/screens/welcome_screen.dart';
import '../../features/settings/presentation/screens/app_settings_screen.dart';
import '../../features/settings/presentation/screens/privacy_center_screen.dart';

/// Returns a [CustomTransitionPage] with a 200 ms [FadeTransition] for all
/// push/pop navigations. Tab-level root routes use [NoTransitionPage] so the
/// bottom-nav switch feels instant.
CustomTransitionPage<void> _fadePage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Read, not watched: watching would rebuild the whole router, back at
  // its initial location, on every handoff message (mobile#320: the
  // "Not signed in" notice then undid the user's tab tap). The router only
  // re-runs its redirect when the navigation gate itself flips.
  final authHandoff = ref.read(authHandoffControllerProvider);
  final navigationGate = _NavigationGate(authHandoff);
  ref.onDispose(navigationGate.dispose);
  final onboardingState = ref.watch(onboardingControllerProvider);
  final welcomeState = ref.watch(welcomeControllerProvider);
  final featureFlags = ref.watch(featureFlagsProvider);
  final walletSendEnabled = ref.watch(walletSendEnabledProvider);

  return GoRouter(
    initialLocation: '/weather',
    refreshListenable: navigationGate,
    redirect: (context, state) {
      if (featureFlags.enableFirstRunWelcome &&
          welcomeState.shouldShowWelcome &&
          state.matchedLocation != '/welcome') {
        return '/welcome';
      }

      if ((!featureFlags.enableFirstRunWelcome ||
              !welcomeState.shouldShowWelcome) &&
          welcomeState.loaded &&
          state.matchedLocation == '/welcome') {
        return '/weather';
      }

      if (featureFlags.enableOnboardingTour &&
          onboardingState.shouldShowTour &&
          state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }

      if ((!featureFlags.enableOnboardingTour ||
              !onboardingState.shouldShowTour) &&
          onboardingState.loaded &&
          state.matchedLocation == '/onboarding') {
        return '/weather';
      }

      // Being signed out is not a reason to leave Weather or Collect: only
      // the wallet needs a session (mobile#320).
      if (!authHandoff.gatesNavigation) {
        return null;
      }

      const walletConnectPaths = <String>{
        '/wallet',
        '/wallet/create',
        '/wallet/import',
        // Public chain data; needs no session.
        '/wallet/chain',
        '/wallet/nodes',
      };

      if (walletConnectPaths.contains(state.matchedLocation)) {
        return null;
      }

      return '/wallet';
    },
    routes: [
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) =>
            _fadePage(key: state.pageKey, child: const WelcomeScreen()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            _fadePage(key: state.pageKey, child: const OnboardingTourScreen()),
      ),
      // Outside the shell: Sky View fills the screen, with no navigation bar.
      GoRoute(
        path: '/weather/ar',
        pageBuilder: (context, state) =>
            _fadePage(key: state.pageKey, child: const ArViewerScreen()),
      ),
      // An indexed stack: every tab keeps its screen, its data and its scroll
      // position while another tab is showing. A branch is built on its first
      // visit, not at launch. Hidden branches run with TickerMode off, which
      // is how a screen knows it is off screen (see ForecastDashboard and
      // ChainScreen).
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/weather',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ForecastDashboard()),
                routes: [
                  GoRoute(
                    path: 'map',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const WeatherMapScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'alerts',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const AlertsScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'alert-settings',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const AlertSettingsScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'stories',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const WeatherStoriesScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'forecast-check',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const ForecastCheckScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'forecast-detail',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: ForecastDetailScreen(
                        currentForecast: state.extra as ForecastModel?,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/collect',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: CollectorDashboard()),
                routes: [
                  GoRoute(
                    path: 'settings',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const SensorSettingsScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'station-transfer',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const StationTransferScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'station-security',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const StationSecurityScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'station-recovery',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const StationRecoveryScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'station-accept',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const StationAcceptScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'validation',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const CollectorValidationScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'field-mode',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const FieldModeScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'challenges',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const FriendChallengesRoute(),
                    ),
                  ),
                  GoRoute(
                    path: 'duels',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const ForecastDuelsScreen(),
                    ),
                    routes: [
                      GoRoute(
                        path: ':id',
                        pageBuilder: (context, state) => _fadePage(
                          key: state.pageKey,
                          child: ForecastDuelScreen(
                            id: state.pathParameters['id'] ?? '',
                          ),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'calibration',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const StationCalibrationScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'imagery',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const ImageryUploadScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'stations',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const PwsDashboardScreen(),
                    ),
                    routes: [
                      GoRoute(
                        path: ':stationId',
                        pageBuilder: (context, state) => _fadePage(
                          key: state.pageKey,
                          child: StationProfileScreen(
                            stationId: state.pathParameters['stationId'] ?? '',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/wallet',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: WalletScreen()),
                routes: [
                  GoRoute(
                    path: 'analytics',
                    builder: (context, state) =>
                        const AnalyticsDashboardScreen(),
                  ),
                  GoRoute(
                    path: 'send',
                    // Hidden in tester (profile) builds; see WalletSendGate.
                    redirect: (_, _) => walletSendEnabled ? null : '/wallet',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const SendScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'receive',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const ReceiveScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'lottery',
                    // Dark-launched until a backend exists (mobile#268).
                    redirect: (_, _) =>
                        featureFlags.enableCarbonLottery ? null : '/wallet',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const CarbonLotteryDashboardScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'notifications',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const PayoutNotificationsScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'chain',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const ChainScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'nodes',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const NetworkNodesScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'faucet',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const FaucetScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'create',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const CreateWalletScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'import',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const ImportWalletScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // The More tab. Its first route is the tab's first screen. Govern
          // shares the branch, so a link to /govern highlights More.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _MoreBranchBack(builder: (_, _) => const MoreScreen()),
                ),
              ),
              GoRoute(
                path: '/govern',
                pageBuilder: (context, state) => _fadePage(
                  key: state.pageKey,
                  child: _MoreBranchBack(
                    toList: true,
                    builder: (_, leading) =>
                        ProposalListScreen(leading: leading),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'proposal',
                    redirect: (context, state) =>
                        state.extra == null ? '/govern' : null,
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: ProposalDetailScreen(
                        proposal: state.extra! as ProposalModel,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'vote',
                    redirect: (context, state) =>
                        state.extra == null ? '/govern' : null,
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: VoteScreen(
                        proposal: state.extra! as ProposalModel,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                // Gate only the achievements surfaces behind the flag: settings
                // and privacy must stay reachable regardless — every tab's gear
                // opens /profile/settings, and the Collect dashboard links straight
                // to /profile/privacy, even when the Profile tab is hidden. More
                // also opens competitions and the leaderboard with the tab hidden.
                redirect: (context, state) {
                  if (featureFlags.enableAchievementsUi) return null;
                  final path = state.uri.path;
                  final gated =
                      path == '/profile' || path.startsWith('/profile/deserts');
                  return gated ? '/weather' : null;
                },
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: AchievementsScreen()),
                routes: [
                  GoRoute(
                    path: 'deserts',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const DataDesertMapScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'competitions',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const CompetitionsScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'leaderboard',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const LeaderboardScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'settings',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const AppSettingsScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'privacy',
                    pageBuilder: (context, state) => _fadePage(
                      key: state.pageKey,
                      child: const PrivacyCenterScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Back on a tab after at least this long, the read-only lists that used to
/// reload on every visit are fetched again, in place.
const tabDataStaleAfter = Duration(minutes: 1);

/// Screens holding a recovery phrase. Leaving one by the navigation bar closes
/// it, as it always did, rather than keeping the phrase in memory and the
/// screenshot block on behind another tab.
const _closeWhenLeft = <String>{'/wallet/create', '/wallet/import'};

class ScaffoldWithNavBar extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  /// In bar order, each with its [StatefulShellBranch] index. Branch order is
  /// not bar order: More is branch [_moreBranch] and sits last on the bar.
  static const _allTabs = [
    (Icons.cloud, 'Weather', 0),
    (Icons.sensors, 'Collect', 1),
    (Icons.account_balance_wallet, 'Wallet', 2),
    (Icons.person, 'Profile', 4),
    (Icons.menu, 'More', _moreBranch),
  ];

  static const _moreBranch = 3;

  @override
  ConsumerState<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends ConsumerState<ScaffoldWithNavBar> {
  final _leftAt = <int, DateTime>{};

  /// The tab to open once the screen in [_closeWhenLeft] has closed.
  int? _openAfterClose;

  /// The tab More was opened from, where Back on its list returns.
  int? _cameToMoreFrom;

  @override
  void didUpdateWidget(ScaffoldWithNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.navigationShell.currentIndex;
    final current = widget.navigationShell.currentIndex;
    final next = _openAfterClose;
    if (next != null) {
      _openAfterClose = null;
      // After its close animation: hidden tabs run no animations, so a screen
      // still closing would stay mounted until its tab came back.
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) widget.navigationShell.goBranch(next);
      });
    }
    if (previous == current) return;
    if (current == ScaffoldWithNavBar._moreBranch) _cameToMoreFrom = previous;
    final now = ref.read(appClockProvider)();
    _leftAt[previous] = now;
    final left = _leftAt[current];
    if (left != null && now.difference(left) >= tabDataStaleAfter) {
      _refreshTabData(current);
    }
  }

  /// A kept tab keeps its auto-disposed providers too, so they no longer
  /// reload by being re-created. The previous value stays on screen meanwhile.
  /// Weather decides for itself: see WeatherNotifier.onVisible.
  void _refreshTabData(int index) {
    switch (index) {
      case 1:
        ref.invalidate(mobileStationStatusProvider);
      case 2:
        ref.invalidate(transactionsProvider);
      case 4:
        ref.invalidate(ownRoleEarningsProvider);
    }
  }

  void _leaveMore() => widget.navigationShell.goBranch(_cameToMoreFrom ?? 0);

  void _selectTab(int index) {
    final shell = widget.navigationShell;
    final current = shell.currentIndex;
    if (index == current) {
      // The tab you are on: back to its first screen.
      shell.goBranch(index, initialLocation: true);
      return;
    }
    final router = GoRouter.of(context);
    if (_closeWhenLeft.contains(router.state.uri.path)) {
      _openAfterClose = index;
      router.go('/wallet');
      return;
    }
    shell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(featureFlagsProvider);
    final tabs = flags.enableAchievementsUi
        ? ScaffoldWithNavBar._allTabs
        : ScaffoldWithNavBar._allTabs.where((t) => t.$2 != 'Profile').toList();

    // The branch, not the top route: Settings is /profile/settings, but opened
    // from Weather it sits on Weather's stack and stays Weather.
    final branch = widget.navigationShell.currentIndex;
    final selected = tabs.indexWhere((t) => t.$3 == branch);
    final selectedIndex = selected < 0 ? 0 : selected;
    void selectBarItem(int item) => _selectTab(tabs[item].$3);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppBreakpoints.medium) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: selectBarItem,
                    labelType: NavigationRailLabelType.all,
                    destinations: tabs
                        .map(
                          (t) => NavigationRailDestination(
                            icon: Icon(t.$1),
                            label: Text(t.$2),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: widget.navigationShell),
              ],
            ),
          );
        }

        return Scaffold(
          body: widget.navigationShell,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: selectedIndex,
            onTap: selectBarItem,
            type: BottomNavigationBarType.fixed,
            items: tabs
                .map(
                  (t) => BottomNavigationBarItem(icon: Icon(t.$1), label: t.$2),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

/// Back at the bottom of the More branch, where a tab would close the app:
/// the list returns to the tab More was opened from, and Govern opened by a
/// link, with no list under it, returns to the list. Anywhere higher up this
/// does nothing and Back is an ordinary pop.
class _MoreBranchBack extends StatelessWidget {
  const _MoreBranchBack({required this.builder, this.toList = false});

  /// Given the app bar's back button, when the screen needs its own.
  final Widget Function(BuildContext, Widget? leading) builder;
  final bool toList;

  @override
  Widget build(BuildContext context) {
    final atBottom = ModalRoute.of(context)?.isFirst ?? false;
    void back() {
      if (toList) {
        context.go('/more');
      } else {
        context
            .findAncestorStateOfType<_ScaffoldWithNavBarState>()
            ?._leaveMore();
      }
    }

    return PopScope(
      canPop: !atBottom,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: builder(
        context,
        atBottom && toList ? BackButton(onPressed: back) : null,
      ),
    );
  }
}

/// Notifies only when [AuthHandoffController.gatesNavigation] changes, not
/// on every handoff message.
class _NavigationGate extends ChangeNotifier {
  _NavigationGate(this._handoff) : _gated = _handoff.gatesNavigation {
    _handoff.addListener(_onHandoffChanged);
  }

  final AuthHandoffController _handoff;
  bool _gated;

  void _onHandoffChanged() {
    final gated = _handoff.gatesNavigation;
    if (gated == _gated) return;
    _gated = gated;
    notifyListeners();
  }

  @override
  void dispose() {
    _handoff.removeListener(_onHandoffChanged);
    super.dispose();
  }
}
