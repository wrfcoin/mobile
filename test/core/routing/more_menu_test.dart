// The More tab: what is on the bar, every entry opening its existing route,
// flags hiding entries, Back, kept tabs, and the signed-out and session gates.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/auth/auth_handoff.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/challenges/presentation/screens/challenges_screen.dart';
import 'package:wrfcoin_mobile/features/competitions/presentation/screens/competitions_screen.dart';
import 'package:wrfcoin_mobile/features/duels/presentation/screens/forecast_duels_screen.dart';
import 'package:wrfcoin_mobile/features/explorer/presentation/screens/chain_screen.dart';
import 'package:wrfcoin_mobile/features/forecast_check/presentation/screens/forecast_check_screen.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/achievements_screen.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/data_desert_map_screen.dart';
import 'package:wrfcoin_mobile/features/gamification/presentation/screens/leaderboard_screen.dart';
import 'package:wrfcoin_mobile/features/governance/presentation/screens/proposal_list_screen.dart';
import 'package:wrfcoin_mobile/features/more/presentation/screens/more_screen.dart';
import 'package:wrfcoin_mobile/features/network_nodes/presentation/screens/network_nodes_screen.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/app_settings_screen.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/ar_viewer_screen.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_dashboard.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/weather_map_screen.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/screenshot_fonts.dart';

class _FixedFlags extends FeatureFlagsNotifier {
  _FixedFlags(this._flags);

  final FeatureFlags _flags;

  @override
  FeatureFlags build() => _flags;
}

const _phone = Size(390, 844);

const _entries = <(String, String, Type)>[
  ('Chain', '/wallet/chain', ChainScreen),
  ('Nodes', '/wallet/nodes', NetworkNodesScreen),
  ('Weather map', '/weather/map', WeatherMapScreen),
  ('Sky View', '/weather/ar', ArViewerScreen),
  ('Forecast check', '/weather/forecast-check', ForecastCheckScreen),
  ('Competitions', '/profile/competitions', CompetitionsScreen),
  ('Duels', '/collect/duels', ForecastDuelsScreen),
  ('Friend Challenges', '/collect/challenges', FriendChallengesRoute),
  ('Leaderboard', '/profile/leaderboard', LeaderboardScreen),
  ('Govern', '/govern', ProposalListScreen),
  ('Settings', '/profile/settings', AppSettingsScreen),
];

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await db.close();
  });

  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    Size size = _phone,
    FeatureFlags? flags,
    bool signedIn = true,
  }) async {
    await loadFlutterCacheFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
        signedIn: signedIn,
        extraOverrides: [
          if (flags != null)
            featureFlagsProvider.overrideWith(() => _FixedFlags(flags)),
        ],
      ),
    );
    await pumpFrames(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>).first),
    ).read(appRouterProvider);
  }

  List<String> barLabels(WidgetTester tester) => tester
      .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
      .items
      .map((i) => i.label!)
      .toList();

  String selectedLabel(WidgetTester tester) {
    final bar = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    return bar.items[bar.currentIndex].label!;
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text(label),
      ),
    );
    await pumpFrames(tester);
  }

  Future<void> tapEntry(WidgetTester tester, String label) async {
    final entry = find.descendant(
      of: find.byType(MoreScreen),
      matching: find.text(label),
    );
    await tester.scrollUntilVisible(
      entry,
      100,
      scrollable: find.descendant(
        of: find.byType(MoreScreen),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(entry);
    await pumpFrames(tester, frames: 2);
    await tester.tap(entry);
    await pumpFrames(tester);
  }

  /// Some screens start a request on open; let its timeout timer finish.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
  }

  testWidgets('the bar is Weather, Collect, Wallet, Profile, More', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(barLabels(tester), [
      'Weather',
      'Collect',
      'Wallet',
      'Profile',
      'More',
    ]);
  });

  testWidgets('the rail on a wide window has the same five', (tester) async {
    await pumpApp(tester, size: const Size(1280, 800));
    final rail = find.byType(NavigationRail);
    for (final label in ['Weather', 'Collect', 'Wallet', 'Profile', 'More']) {
      expect(
        find.descendant(of: rail, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: rail, matching: find.text('Govern')),
      findsNothing,
    );

    await tester.tap(find.descendant(of: rail, matching: find.text('More')));
    await pumpFrames(tester);
    expect(find.byType(MoreScreen), findsOneWidget);
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the list is grouped under plain headings', (tester) async {
    await pumpApp(tester);
    await tapTab(tester, 'More');
    for (final heading in ['Explore', 'Forecasting', 'Community']) {
      expect(find.text(heading), findsOneWidget);
    }
    final order = [
      'Explore',
      'Chain',
      'Nodes',
      'Weather map',
      'Sky View',
      'Forecasting',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        tester.getTopLeft(find.text(order[i])).dy,
        greaterThan(tester.getTopLeft(find.text(order[i - 1])).dy),
        reason: order[i],
      );
    }
  });

  for (final (label, path, screen) in _entries) {
    testWidgets('$label opens $path; Back returns to the list on More', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      await tapTab(tester, 'More');
      await tapEntry(tester, label);
      await pumpUntilFound(tester, find.byType(screen));
      expect(router.state.uri.path, path);
      // Sky View fills the screen, with no bar to highlight.
      if (path != '/weather/ar') expect(selectedLabel(tester), 'More');

      router.pop();
      await pumpFrames(tester);
      expect(find.byType(screen), findsNothing);
      expect(find.byType(MoreScreen), findsOneWidget);
      expect(selectedLabel(tester), 'More');
      await finish(tester);
    });
  }

  group('flags', () {
    testWidgets('Friend Challenges hides with its flag, the rest stay', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 1400),
        flags: const FeatureFlags(enableFriendChallenges: false),
      );
      await tapTab(tester, 'More');
      expect(find.text('Friend Challenges'), findsNothing);
      for (final (label, _, _) in _entries) {
        if (label != 'Friend Challenges') {
          expect(find.text(label), findsOneWidget, reason: label);
        }
      }
    });

    testWidgets('with Profile off, Competitions and Leaderboard still open', (
      tester,
    ) async {
      final router = await pumpApp(
        tester,
        flags: const FeatureFlags(enableAchievementsUi: false),
      );
      expect(barLabels(tester), ['Weather', 'Collect', 'Wallet', 'More']);

      await tapTab(tester, 'More');
      expect(selectedLabel(tester), 'More');
      expect(find.byType(MoreScreen), findsOneWidget);

      await tapEntry(tester, 'Competitions');
      await pumpUntilFound(tester, find.byType(CompetitionsScreen));
      expect(selectedLabel(tester), 'More');
      router.pop();
      await pumpFrames(tester);

      await tapEntry(tester, 'Leaderboard');
      await pumpUntilFound(tester, find.byType(LeaderboardScreen));
      expect(router.state.uri.path, '/profile/leaderboard');
      expect(selectedLabel(tester), 'More');
      await finish(tester);
    });

    testWidgets('with Profile off, its own screens stay gated', (tester) async {
      final router = await pumpApp(
        tester,
        flags: const FeatureFlags(enableAchievementsUi: false),
      );
      for (final path in ['/profile', '/profile/deserts']) {
        router.go(path);
        await pumpFrames(tester);
        expect(router.state.uri.path, '/weather', reason: path);
      }
      expect(find.byType(AchievementsScreen), findsNothing);
      expect(find.byType(DataDesertMapScreen), findsNothing);
    });
  });

  group('deep links', () {
    testWidgets('/govern opens Govern with More highlighted', (tester) async {
      final router = await pumpApp(tester);
      router.go('/govern');
      await pumpUntilFound(tester, find.byType(ProposalListScreen));
      expect(selectedLabel(tester), 'More');
      expect(router.state.uri.path, '/govern');
    });

    testWidgets('Back from a linked /govern goes to the list, then the tab', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      await tapTab(tester, 'Collect');
      router.go('/govern');
      await pumpUntilFound(tester, find.byType(ProposalListScreen));

      await tester.tap(find.byType(BackButton));
      await pumpFrames(tester);
      expect(router.state.uri.path, '/more');
      expect(find.byType(MoreScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(router.state.uri.path, '/collect');
      expect(selectedLabel(tester), 'Collect');
    });

    testWidgets('the system Back on a linked /govern goes to the list', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      router.go('/govern');
      await pumpUntilFound(tester, find.byType(ProposalListScreen));
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(router.state.uri.path, '/more');
    });

    testWidgets('tapping More on Govern goes to the list', (tester) async {
      final router = await pumpApp(tester);
      router.go('/govern');
      await pumpUntilFound(tester, find.byType(ProposalListScreen));
      await tapTab(tester, 'More');
      expect(router.state.uri.path, '/more');
      expect(find.byType(MoreScreen), findsOneWidget);
    });

    final bars = <String, String>{
      '/wallet/chain': 'Wallet',
      '/wallet/nodes': 'Wallet',
      '/weather/map': 'Weather',
      '/weather/forecast-check': 'Weather',
      '/profile/competitions': 'Profile',
      '/collect/duels': 'Collect',
    };
    for (final link in bars.entries) {
      testWidgets('${link.key} still resolves under ${link.value}', (
        tester,
      ) async {
        final router = await pumpApp(tester);
        router.go(link.key);
        await pumpFrames(tester, frames: 8);
        expect(router.state.uri.path, link.key);
        expect(selectedLabel(tester), link.value);
        await finish(tester);
      });
    }

    testWidgets('/weather/ar still opens over the shell', (tester) async {
      final router = await pumpApp(tester);
      router.go('/weather/ar');
      await pumpFrames(tester);
      expect(find.byType(ArViewerScreen), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(router.state.uri.path, '/weather/ar');
      await finish(tester);
    });
  });

  group('Back and kept tabs', () {
    testWidgets(
      'the system Back on the list returns to the tab you came from',
      (tester) async {
        final router = await pumpApp(tester);
        await tapTab(tester, 'Wallet');
        await tapTab(tester, 'More');
        await tester.binding.handlePopRoute();
        await pumpFrames(tester);
        expect(router.state.uri.path, '/wallet');
        expect(selectedLabel(tester), 'Wallet');
      },
    );

    testWidgets('Weather is the same screen after a trip through More', (
      tester,
    ) async {
      await pumpApp(tester);
      final weather = tester.state(find.byType(ForecastDashboard));
      await tapTab(tester, 'More');
      expect(find.byType(ForecastDashboard), findsNothing);
      await tapEntry(tester, 'Nodes');
      await tapTab(tester, 'Weather');
      expect(tester.state(find.byType(ForecastDashboard)), same(weather));
      await finish(tester);
    });

    testWidgets('More keeps its open screen across tabs; tapping it resets', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      await tapTab(tester, 'More');
      await tapEntry(tester, 'Nodes');
      expect(find.byType(NetworkNodesScreen), findsOneWidget);

      await tapTab(tester, 'Collect');
      expect(selectedLabel(tester), 'Collect');
      await tapTab(tester, 'More');
      expect(find.byType(NetworkNodesScreen), findsOneWidget);
      expect(selectedLabel(tester), 'More');

      await tapTab(tester, 'More');
      expect(router.state.uri.path, '/more');
      expect(find.byType(NetworkNodesScreen), findsNothing);
      await finish(tester);
    });

    testWidgets('Chain from Wallet stays on Wallet', (tester) async {
      final router = await pumpApp(tester);
      await tapTab(tester, 'Wallet');
      await tester.tap(find.byTooltip('Chain'));
      await pumpUntilFound(tester, find.byType(ChainScreen));
      expect(selectedLabel(tester), 'Wallet');
      router.pop();
      await pumpFrames(tester);
      expect(router.state.uri.path, '/wallet');
      await finish(tester);
    });
  });

  group('shortcuts stay', () {
    testWidgets(
      'Forecast check on Weather, Competitions on Profile, the gear',
      (tester) async {
        final router = await pumpApp(tester);
        expect(find.byTooltip('Forecast check'), findsOneWidget);
        router.go('/profile');
        await pumpFrames(tester);
        expect(find.byTooltip('Weekly competition'), findsOneWidget);
        expect(find.byTooltip('Settings'), findsOneWidget);
      },
    );
  });

  group('fit', () {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('the list and the bar fit 390 px at text scale $scale', (
        tester,
      ) async {
        // Scaled once on More: this is about More, and the first tab has
        // overflows of its own at large text scales.
        await pumpApp(tester);
        await tapTab(tester, 'More');
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await pumpFrames(tester);
        expect(find.byType(MoreScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        final context = tester.element(find.text('Explore'));
        expect(MediaQuery.textScalerOf(context).scale(10), 10 * scale);
        await tester.scrollUntilVisible(
          find.text('Settings'),
          100,
          scrollable: find.descendant(
            of: find.byType(MoreScreen),
            matching: find.byType(Scrollable),
          ),
        );
        await pumpFrames(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('signed out and the session gate', () {
    testWidgets('signed out, More and its entries stay put', (tester) async {
      final router = await pumpApp(tester, signedIn: false);
      for (final (label, path, screen) in _entries) {
        await tapTab(tester, 'More');
        if (router.state.uri.path != '/more') await tapTab(tester, 'More');
        expect(router.state.uri.path, '/more');
        await tapEntry(tester, label);
        await pumpUntilFound(tester, find.byType(screen));
        expect(router.state.uri.path, path, reason: label);
        router.pop();
        await pumpFrames(tester);
      }
      await finish(tester);
    });

    testWidgets('signed out, a linked /govern is not sent to the wallet', (
      tester,
    ) async {
      final router = await pumpApp(tester, signedIn: false);
      ProviderScope.containerOf(
            tester.element(find.byType(Router<Object>).first),
          )
          .read(authHandoffControllerProvider)
          .requireWalletConnect(
            reason: AuthHandoffReason.notSignedIn,
            message: 'Not signed in (test)',
          );
      await pumpFrames(tester);
      router.go('/govern');
      await pumpFrames(tester);
      expect(router.state.uri.path, '/govern');
      await tapTab(tester, 'More');
      expect(router.state.uri.path, '/more');
    });

    for (final reason in const [
      AuthHandoffReason.sessionExpired,
      AuthHandoffReason.unsupportedWallet,
    ]) {
      testWidgets('${reason.name} still sends More and Govern to the wallet', (
        tester,
      ) async {
        final router = await pumpApp(tester);
        await tapTab(tester, 'More');
        expect(router.state.uri.path, '/more');

        ProviderScope.containerOf(
              tester.element(find.byType(Router<Object>).first),
            )
            .read(authHandoffControllerProvider)
            .requireWalletConnect(reason: reason, message: 'Reconnect (test)');
        await pumpFrames(tester);
        expect(router.state.uri.path, '/wallet');
        expect(selectedLabel(tester), 'Wallet');

        await tapTab(tester, 'More');
        expect(router.state.uri.path, '/wallet');
        expect(selectedLabel(tester), 'Wallet');

        router.go('/govern');
        await pumpFrames(tester);
        expect(router.state.uri.path, '/wallet');

        // Chain and Nodes need no session, as before.
        router.go('/wallet/chain');
        await pumpFrames(tester);
        expect(router.state.uri.path, '/wallet/chain');
        await finish(tester);
      });
    }
  });
}
