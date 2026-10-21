import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_handoff.dart';
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
import '../../features/challenges/presentation/screens/challenges_screen.dart';
import '../../features/wallet/presentation/screens/wallet_screen.dart';
import '../../features/analytics/presentation/screens/analytics_dashboard_screen.dart';
import '../../features/wallet/presentation/screens/send_screen.dart';
import '../../features/wallet/presentation/screens/receive_screen.dart';
import '../../features/wallet/presentation/screens/create_wallet_screen.dart';
import '../../features/wallet/presentation/screens/import_wallet_screen.dart';
import '../../features/carbon_lottery/presentation/screens/carbon_lottery_dashboard_screen.dart';
import '../../features/faucet/presentation/screens/faucet_screen.dart';
import '../../features/explorer/presentation/screens/chain_screen.dart';
import '../../features/governance/presentation/screens/proposal_list_screen.dart';
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
      ShellRoute(
        builder: (context, state, child) => ScaffoldWithNavBar(child: child),
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
                path: 'ar',
                pageBuilder: (context, state) => _fadePage(
                  key: state.pageKey,
                  child: const ArViewerScreen(),
                ),
              ),
              GoRoute(
                path: 'alerts',
                pageBuilder: (context, state) =>
                    _fadePage(key: state.pageKey, child: const AlertsScreen()),
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
          GoRoute(
            path: '/wallet',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: WalletScreen()),
            routes: [
              GoRoute(
                path: 'analytics',
                builder: (context, state) => const AnalyticsDashboardScreen(),
              ),
              GoRoute(
                path: 'send',
                // Hidden in tester (profile) builds; see WalletSendGate.
                redirect: (_, _) => walletSendEnabled ? null : '/wallet',
                pageBuilder: (context, state) =>
                    _fadePage(key: state.pageKey, child: const SendScreen()),
              ),
              GoRoute(
                path: 'receive',
                pageBuilder: (context, state) =>
                    _fadePage(key: state.pageKey, child: const ReceiveScreen()),
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
                path: 'chain',
                pageBuilder: (context, state) =>
                    _fadePage(key: state.pageKey, child: const ChainScreen()),
              ),
              GoRoute(
                path: 'faucet',
                pageBuilder: (context, state) =>
                    _fadePage(key: state.pageKey, child: const FaucetScreen()),
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
          GoRoute(
            path: '/govern',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProposalListScreen()),
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
                  child: VoteScreen(proposal: state.extra! as ProposalModel),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            // Gate only the achievements surfaces behind the flag: settings
            // and privacy must stay reachable regardless — the Collect
            // dashboard links straight to /profile/privacy and
            // /profile/settings even when the Profile tab is hidden.
            redirect: (context, state) {
              if (featureFlags.enableAchievementsUi) return null;
              final path = state.uri.path;
              final gated =
                  path == '/profile' ||
                  path.startsWith('/profile/deserts') ||
                  path.startsWith('/profile/leaderboard');
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
  );
});

class ScaffoldWithNavBar extends ConsumerWidget {
  final Widget child;

  const ScaffoldWithNavBar({super.key, required this.child});

  static const _allTabs = [
    ('/weather', Icons.cloud, 'Weather'),
    ('/collect', Icons.sensors, 'Collect'),
    ('/wallet', Icons.account_balance_wallet, 'Earnings'),
    ('/govern', Icons.how_to_vote, 'Govern'),
    ('/profile', Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);
    final tabs = flags.enableAchievementsUi
        ? _allTabs
        : _allTabs.where((t) => t.$1 != '/profile').toList();

    final uri = GoRouterState.of(context).uri;
    final pathFromHash = uri.fragment.startsWith('/') ? uri.fragment : '';
    final location = uri.path.isNotEmpty
        ? uri.path
        : pathFromHash.isNotEmpty
        ? pathFromHash
        : uri.toString();
    final currentIndex = tabs.indexWhere((t) => location.startsWith(t.$1));
    final selectedIndex = currentIndex < 0 ? 0 : currentIndex;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppBreakpoints.medium) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (index) =>
                        context.go(tabs[index].$1),
                    labelType: NavigationRailLabelType.all,
                    destinations: tabs
                        .map(
                          (t) => NavigationRailDestination(
                            icon: Icon(t.$2),
                            label: Text(t.$3),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          );
        }

        return Scaffold(
          body: child,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: selectedIndex,
            onTap: (index) => context.go(tabs[index].$1),
            type: BottomNavigationBarType.fixed,
            items: tabs
                .map(
                  (t) => BottomNavigationBarItem(icon: Icon(t.$2), label: t.$3),
                )
                .toList(),
          ),
        );
      },
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
