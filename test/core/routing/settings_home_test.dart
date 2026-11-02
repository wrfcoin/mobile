// Settings lives in one place: the same gear on every main tab opens it, what
// moved there is gone from the tabs, and every old route still resolves.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/features/calibration/presentation/station_calibration_screen.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/collector_validation_screen.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/sensor_settings_screen.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_accept_screen.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_recovery_screen.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_security_screen.dart';
import 'package:wrfcoin_mobile/features/collector/presentation/screens/station_transfer_screen.dart';
import 'package:wrfcoin_mobile/features/field_diagnostics/presentation/screens/field_mode_screen.dart';
import 'package:wrfcoin_mobile/features/notifications/presentation/payout_notifications_screen.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/app_settings_screen.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/privacy_center_screen.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/widgets/settings_gear_button.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/alert_settings_screen.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/alerts_screen.dart';
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

const _tabs = <(String, String)>[
  ('/weather', 'Weather'),
  ('/collect', 'Collect'),
  ('/wallet', 'Earnings'),
  ('/govern', 'Govern'),
  ('/profile', 'Profile'),
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
    await tester.pumpWidget(
      await buildTestApp(
        db: db,
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

  int selectedTab(WidgetTester tester) => tester
      .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
      .currentIndex;

  /// The whole action row and the title fit inside the app bar at this width.
  void expectAppBarFits(WidgetTester tester, Size size) {
    final appBar = find.byType(AppBar).last;
    final actions = find.descendant(
      of: appBar,
      matching: find.byType(IconButton),
    );
    expect(actions, findsWidgets);
    var leftmost = size.width;
    for (final element in actions.evaluate()) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      if (rect.left < leftmost) leftmost = rect.left;
    }
    final title = tester.widget<AppBar>(appBar).title! as Text;
    final titleBox = tester.getRect(
      find.descendant(of: appBar, matching: find.text(title.data!)),
    );
    expect(titleBox.right, lessThanOrEqualTo(leftmost));
  }

  for (final (path, label) in _tabs) {
    for (final size in const [_phone, Size(1280, 800)]) {
      testWidgets('$label has the gear and it fits at ${size.width} px', (
        tester,
      ) async {
        final router = await pumpApp(tester, size: size);
        router.go(path);
        await pumpFrames(tester);

        expect(find.byType(SettingsGearButton), findsOneWidget);
        final gear = tester.widget<Icon>(
          find.descendant(
            of: find.byType(SettingsGearButton),
            matching: find.byType(Icon),
          ),
        );
        expect(gear.icon, Icons.settings);
        expectAppBarFits(tester, size);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('gear on $label opens Settings and Back returns to $label', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      router.go(path);
      await pumpFrames(tester);
      final tabIndex = selectedTab(tester);

      await tester.tap(find.byType(SettingsGearButton));
      await pumpUntilFound(tester, find.byType(AppSettingsScreen));
      await pumpFrames(tester);
      expect(selectedTab(tester), tabIndex, reason: 'tab stays selected');
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(BackButton));
      await pumpFrames(tester);
      expect(find.byType(AppSettingsScreen), findsNothing);
      expect(find.byType(SettingsGearButton), findsOneWidget);
      expect(router.state.uri.path, path);
      expect(selectedTab(tester), tabIndex);
    });
  }

  testWidgets('Back steps from an entry to Settings and then to the tab', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.go('/wallet');
    await pumpFrames(tester);

    await tester.tap(find.byType(SettingsGearButton));
    await pumpUntilFound(tester, find.text('Sensor settings'));
    await pumpFrames(tester);
    await tester.ensureVisible(find.text('Sensor settings'));
    await pumpFrames(tester);
    await tester.tap(find.text('Sensor settings'));
    await pumpUntilFound(tester, find.byType(SensorSettingsScreen));
    await pumpFrames(tester);

    await tester.tap(find.byType(BackButton).last);
    await pumpFrames(tester);
    expect(find.byType(SensorSettingsScreen), findsNothing);
    expect(find.byType(AppSettingsScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton).last);
    await pumpFrames(tester);
    expect(find.byType(AppSettingsScreen), findsNothing);
    expect(router.state.uri.path, '/wallet');
  });

  testWidgets('the gear still opens Settings with the Profile tab hidden', (
    tester,
  ) async {
    final router = await pumpApp(
      tester,
      flags: const FeatureFlags(enableAchievementsUi: false),
    );
    router.go('/collect');
    await pumpFrames(tester);
    expect(find.text('Profile'), findsNothing);

    await tester.tap(find.byType(SettingsGearButton));
    await pumpUntilFound(tester, find.byType(AppSettingsScreen));
    await pumpFrames(tester);
    expect(selectedTab(tester), 1);

    await tester.tap(find.byType(BackButton));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/collect');
  });

  testWidgets('Collect no longer lists what moved to Settings', (tester) async {
    final router = await pumpApp(tester);
    router.go('/collect');
    await pumpFrames(tester);

    expect(find.byTooltip('Privacy center'), findsNothing);
    expect(find.byTooltip('Sensor settings'), findsNothing);
    expect(find.byTooltip('Collector validation'), findsNothing);
    // Not part of the move.
    expect(find.byTooltip('Field mode'), findsOneWidget);
    expect(find.byTooltip('Challenges'), findsOneWidget);
  });

  testWidgets('a turned-off feature keeps its app bar entry hidden', (
    tester,
  ) async {
    final router = await pumpApp(
      tester,
      flags: const FeatureFlags(
        enableFriendChallenges: false,
        enableAnalyticsDashboard: false,
      ),
    );
    router.go('/collect');
    await pumpFrames(tester);
    expect(find.byTooltip('Challenges'), findsNothing);
    expect(find.byType(SettingsGearButton), findsOneWidget);

    router.go('/wallet');
    await pumpFrames(tester);
    expect(find.byTooltip('Analytics'), findsNothing);
    expect(find.byType(SettingsGearButton), findsOneWidget);
  });

  testWidgets('Wallet app bar fits at 390 px with every optional entry on', (
    tester,
  ) async {
    final router = await pumpApp(
      tester,
      flags: const FeatureFlags(enableAnalyticsDashboard: true),
    );
    router.go('/wallet');
    await pumpFrames(tester);
    expect(find.byTooltip('Analytics'), findsOneWidget);
    expectAppBarFits(tester, _phone);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent app bar entries stay on screen at 390 px', (
    tester,
  ) async {
    final router = await pumpApp(tester);

    router.go('/weather');
    await pumpFrames(tester);
    expect(find.byTooltip('Forecast check').hitTestable(), findsOneWidget);

    router.go('/profile');
    await pumpFrames(tester);
    expect(find.byTooltip('Weekly competition').hitTestable(), findsOneWidget);

    router.go('/wallet/chain');
    await pumpFrames(tester);
    expect(
      find.byTooltip('Producers and bonded nodes').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings does not overflow at 390 px', (tester) async {
    final router = await pumpApp(tester, size: const Size(390, 3200));
    router.go('/profile/settings');
    await pumpFrames(tester);
    expect(find.text('About'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  final deepLinks = <String, Type>{
    '/profile/settings': AppSettingsScreen,
    '/profile/privacy': PrivacyCenterScreen,
    '/collect/settings': SensorSettingsScreen,
    '/collect/validation': CollectorValidationScreen,
    '/collect/field-mode': FieldModeScreen,
    '/collect/calibration': StationCalibrationScreen,
    '/collect/station-security': StationSecurityScreen,
    '/collect/station-recovery': StationRecoveryScreen,
    '/collect/station-transfer': StationTransferScreen,
    '/collect/station-accept': StationAcceptScreen,
    '/weather/alert-settings': AlertSettingsScreen,
    '/weather/alerts': AlertsScreen,
    '/wallet/notifications': PayoutNotificationsScreen,
  };
  for (final link in deepLinks.entries) {
    testWidgets('deep link ${link.key} still resolves', (tester) async {
      final router = await pumpApp(tester);
      router.go(link.key);
      await pumpUntilFound(tester, find.byType(link.value));
      expect(router.state.uri.path, link.key);
      // Some screens start a request on open; let its timeout timer finish.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 2));
    });
  }

  testWidgets('a blocked Collect screen links straight to Privacy Center', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'privacy.sensor_collection': false,
      'privacy.location_collection': false,
    });
    final router = await pumpApp(tester);
    router.go('/collect');
    await pumpFrames(tester);

    await tester.tap(find.text('Review'));
    await pumpUntilFound(tester, find.byType(PrivacyCenterScreen));
  });

  testWidgets('Payout notifications moved from Earnings to Settings', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.go('/wallet');
    await pumpFrames(tester);
    expect(find.byTooltip('Payout notifications'), findsNothing);

    await tester.tap(find.byType(SettingsGearButton));
    await pumpUntilFound(tester, find.text('Payout notifications'));
    await pumpFrames(tester);
    await tester.ensureVisible(find.text('Payout notifications'));
    await pumpFrames(tester);
    await tester.tap(find.text('Payout notifications'));
    await pumpUntilFound(tester, find.byType(PayoutNotificationsScreen));
  });

  testWidgets('Weather no longer has the Alert Settings button', (
    tester,
  ) async {
    final router = await pumpApp(tester, size: const Size(390, 3000));
    router.go('/weather');
    await pumpFrames(tester);
    expect(find.text('Alert Settings'), findsNothing);
    // The other quick action in that row stays.
    expect(find.text('Sky View'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
