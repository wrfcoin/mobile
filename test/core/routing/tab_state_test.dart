// Switching tabs keeps each tab as it was: no reload, no spinner, the same
// scroll position. Weather still refreshes when it is old, keeps what it has
// when a refresh fails, and says how old it is.
import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:fpdart/fpdart.dart' show Either, Left;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wrfcoin_mobile/core/errors/failures.dart';
import 'package:wrfcoin_mobile/core/feature_flags/feature_flags.dart';
import 'package:wrfcoin_mobile/core/routing/app_router.dart';
import 'package:wrfcoin_mobile/core/time/app_clock.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/screens/app_settings_screen.dart';
import 'package:wrfcoin_mobile/features/settings/presentation/widgets/settings_gear_button.dart';
import 'package:wrfcoin_mobile/features/wallet/data/models/transaction_page.dart';
import 'package:wrfcoin_mobile/features/wallet/domain/repositories/wallet_repository.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/create_wallet_screen.dart';
import 'package:wrfcoin_mobile/features/weather/data/models/forecast_model.dart';
import 'package:wrfcoin_mobile/features/weather/data/weather_location_resolver.dart';
import 'package:wrfcoin_mobile/features/wallet/presentation/screens/recovery_phrase_screen.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/providers/weather_provider.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/forecast_dashboard.dart';
import 'package:wrfcoin_mobile/features/weather/presentation/screens/weather_map_screen.dart';
import 'package:wrfcoin_mobile/services/storage/local_db.dart';

import '../../test_helpers/app_harness.dart';
import '../../test_helpers/fakes.dart';
import '../../test_helpers/screenshot_fonts.dart';

const _forecast = ForecastModel(
  temperature: 20,
  humidity: 55,
  windSpeed: 18,
  location: 'Your area',
  timestamp: '2026-03-10T13:30:00Z',
);

class _CountingWeather extends FakeWeatherRepository {
  _CountingWeather() : super(forecast: _forecast);

  int forecastCalls = 0;
  bool failForecast = false;
  Completer<void>? hold;

  @override
  Future<Either<Failure, ForecastModel>> getForecast(
    CoarseLocation location,
  ) async {
    forecastCalls++;
    await hold?.future;
    if (failForecast) return const Left(ServerFailure('down'));
    return super.getForecast(location);
  }
}

class _CountingWallet extends FakeWalletRepository {
  int transactionCalls = 0;

  @override
  Future<Either<Failure, TransactionPage>> getTransactions(
    String address, {
    int offset = 0,
    int limit = 20,
    CancelToken? cancelToken,
  }) {
    transactionCalls++;
    return super.getTransactions(
      address,
      offset: offset,
      limit: limit,
      cancelToken: cancelToken,
    );
  }
}

/// [peek] and [resolve] answer from a location the test can change.
class _MovableResolver extends WeatherLocationResolver {
  _MovableResolver(this.location);

  CoarseLocation? location;
  int resolves = 0;

  WeatherLocationResult get _result => location == null
      ? const WeatherLocationResult.unavailable(
          LocationUnavailableReason.permissionDenied,
        )
      : WeatherLocationResult.located(location!);

  @override
  Future<WeatherLocationResult> resolve() async {
    resolves++;
    return _result;
  }

  @override
  Future<WeatherLocationResult?> peek() async => _result;
}

class _FixedFlags extends FeatureFlagsNotifier {
  _FixedFlags(this._flags);
  final FeatureFlags _flags;
  @override
  FeatureFlags build() => _flags;
}

void main() {
  late AppDatabase db;
  late _CountingWeather weather;
  late _MovableResolver resolver;
  late DateTime now;

  setUp(() {
    db = createTestDatabase();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    weather = _CountingWeather();
    resolver = _MovableResolver(CoarseLocation.round(45, -93));
    now = DateTime(2026, 11, 1, 12);
  });

  tearDown(() async {
    await db.close();
  });

  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    Size size = const Size(390, 500),
    FeatureFlags? flags,
    WalletRepository? walletRepository,
    bool signedIn = false,
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
        weatherRepository: weather,
        weatherLocationResolver: resolver,
        walletRepository: walletRepository,
        signedIn: signedIn,
        extraOverrides: [
          appClockProvider.overrideWithValue(() => now),
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

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text(label),
      ),
    );
    await pumpFrames(tester);
  }

  int selectedTab(WidgetTester tester) => tester
      .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
      .currentIndex;

  ScrollPosition weatherScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ForecastDashboard),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('a tab switch does not reload Weather or lose its scroll', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(weather.forecastCalls, 1);

    final scrolled = weatherScroll(tester);
    expect(scrolled.maxScrollExtent, greaterThan(100));
    scrolled.jumpTo(100);
    await tester.pump();
    final screen = tester.state(find.byType(ForecastDashboard));

    for (final other in const ['Collect', 'Wallet', 'Profile', 'More']) {
      await tapTab(tester, other);
      expect(find.byType(ForecastDashboard), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Weather'),
        ),
      );
      // Back on the very next frames, with nothing loading.
      await tester.pump();
      await tester.pump();
      expect(find.text('Loading local forecast and alerts...'), findsNothing);
      expect(find.byType(ForecastDashboard), findsOneWidget);
      expect(tester.state(find.byType(ForecastDashboard)), same(screen));
      expect(weatherScroll(tester).pixels, 100);
    }
    expect(weather.forecastCalls, 1, reason: 'no reload for any tab switch');
    // The short window keeps Weather scrollable; a fixed-height card on
    // another tab may overflow at this height. Not what is under test here.
    tester.takeException();
  });

  testWidgets('old weather refreshes on return, keeping the screen', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapTab(tester, 'Collect');

    now = now.add(weatherStaleAfter);
    weather.hold = Completer<void>();
    await tapTab(tester, 'Weather');

    expect(weather.forecastCalls, 2);
    expect(find.text('Loading local forecast and alerts...'), findsNothing);
    expect(find.textContaining('Updating…'), findsOneWidget);
    expect(find.text('Your area'), findsWidgets);

    weather.hold!.complete();
    await pumpFrames(tester);
    expect(find.text('Updated 12:10'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the weather and says how old it is', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapTab(tester, 'Collect');

    // The saved copy has aged out too (15 min): only the old weather is left.
    await tester.runAsync(
      () => db.deleteOfflineData(
        'weather:forecast:${resolver.location!.pathSegment}',
      ),
    );
    now = now.add(const Duration(minutes: 25));
    weather.failForecast = true;
    await tapTab(tester, 'Weather');

    expect(weather.forecastCalls, 2);
    expect(find.text('Your area'), findsWidgets);
    expect(
      find.text("Couldn't refresh. Last updated 12:00 (25 min ago)."),
      findsOneWidget,
    );
    // A failing backend is not hit on every return.
    await tapTab(tester, 'Collect');
    await tapTab(tester, 'Weather');
    expect(weather.forecastCalls, 2);
  });

  testWidgets('a failed refresh with a saved copy says it is the saved copy', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapTab(tester, 'Collect');

    now = now.add(weatherStaleAfter);
    weather.failForecast = true;
    await tapTab(tester, 'Weather');

    expect(find.text('Your area'), findsWidgets);
    expect(find.textContaining('showing data cached at'), findsOneWidget);
  });

  testWidgets('the note ages and the tab refreshes while left open', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Updated 12:00'), findsOneWidget);

    now = now.add(weatherStaleAfter);
    await tester.pump(const Duration(minutes: 1));
    await pumpFrames(tester);
    expect(weather.forecastCalls, 2);
    expect(find.text('Updated 12:10'), findsOneWidget);
  });

  testWidgets('nothing is fetched for Weather while another tab shows', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapTab(tester, 'Collect');
    now = now.add(const Duration(hours: 1));
    await tester.pump(const Duration(minutes: 5));
    expect(weather.forecastCalls, 1);
  });

  testWidgets('pull to refresh still loads while the weather is fresh', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.drag(find.byType(ForecastDashboard), const Offset(0, 400));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await pumpFrames(tester);
    expect(weather.forecastCalls, 2);
  });

  testWidgets('a revoked permission on return replaces the weather', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapTab(tester, 'Collect');

    resolver.location = null;
    await tapTab(tester, 'Weather');

    expect(find.text('Your area'), findsNothing);
    expect(find.text('Updated 12:00'), findsNothing);
    expect(weather.forecastCalls, 1, reason: 'no request without a location');

    resolver.location = CoarseLocation.round(45, -93);
    await tapTab(tester, 'Collect');
    await tapTab(tester, 'Weather');
    expect(weather.forecastCalls, 2);
    expect(find.text('Your area'), findsWidgets);
  });

  testWidgets('a new place never shows the old place on a failed load', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapTab(tester, 'Collect');

    resolver.location = CoarseLocation.round(30, -90);
    weather.failForecast = true;
    await tapTab(tester, 'Weather');

    expect(weather.forecastCalls, 2);
    expect(find.textContaining("Couldn't refresh"), findsNothing);
    expect(find.text('Your area'), findsNothing);
  });

  testWidgets('a pushed screen on a tab is still there on return', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.push('/weather/map');
    await pumpFrames(tester);
    expect(find.byType(WeatherMapScreen), findsOneWidget);

    await tapTab(tester, 'Collect');
    expect(find.byType(WeatherMapScreen), findsNothing);
    await tapTab(tester, 'Weather');
    expect(find.byType(WeatherMapScreen), findsOneWidget);

    // Tapping the tab you are on goes back to its first screen.
    await tapTab(tester, 'Weather');
    expect(find.byType(WeatherMapScreen), findsNothing);
    expect(find.byType(ForecastDashboard), findsOneWidget);
    expect(router.state.uri.path, '/weather');
  });

  testWidgets('the gear on Weather stays on Weather across a switch', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byType(SettingsGearButton));
    await pumpUntilFound(tester, find.byType(AppSettingsScreen));
    await pumpFrames(tester);
    expect(selectedTab(tester), 0);

    await tapTab(tester, 'Collect');
    expect(selectedTab(tester), 1);
    expect(find.byType(AppSettingsScreen), findsNothing);

    await tapTab(tester, 'Weather');
    expect(selectedTab(tester), 0);
    expect(find.byType(AppSettingsScreen), findsOneWidget);
  });

  testWidgets('a settings deep link with Profile hidden does not crash', (
    tester,
  ) async {
    final router = await pumpApp(
      tester,
      flags: const FeatureFlags(enableAchievementsUi: false),
    );
    router.go('/profile/settings');
    await pumpFrames(tester);
    expect(find.byType(AppSettingsScreen), findsOneWidget);
    expect(selectedTab(tester), 0);
    expect(tester.takeException(), isNull);

    await tapTab(tester, 'Weather');
    expect(find.byType(ForecastDashboard), findsOneWidget);
  });

  testWidgets('leaving the recovery phrase screen closes it', (tester) async {
    final router = await pumpApp(tester);
    router.go('/wallet/create');
    await pumpFrames(tester);
    expect(find.byType(CreateWalletScreen), findsOneWidget);

    await tapTab(tester, 'Collect');
    expect(router.state.uri.path, '/collect');
    expect(
      find.byType(CreateWalletScreen, skipOffstage: false),
      findsNothing,
      reason: 'not kept mounted behind another tab',
    );
    await tapTab(tester, 'Wallet');
    expect(router.state.uri.path, '/wallet');
  });

  group('the guarded phrase backup', () {
    Finder phrase() => find.byType(RecoveryPhraseScreen, skipOffstage: false);

    for (final size in const [Size(390, 500), Size(1280, 800)]) {
      testWidgets('opens over the shell at ${size.width.toInt()} px, with no '
          'tab to leave it for', (tester) async {
        final router = await pumpApp(tester, size: size);
        router.push('/profile/settings');
        await pumpFrames(tester);
        router.push('/wallet/recovery-phrase');
        await pumpFrames(tester);
        expect(find.byType(RecoveryPhraseScreen), findsOneWidget);
        expect(find.byType(BottomNavigationBar), findsNothing);
        expect(find.byType(NavigationRail), findsNothing);

        router.pop();
        await pumpFrames(tester);
        expect(find.byType(AppSettingsScreen), findsOneWidget);
        expect(phrase(), findsNothing, reason: 'closed, not kept');
      });
    }

    testWidgets('closes when something else takes the app to a tab', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      router.push('/wallet/recovery-phrase');
      await pumpFrames(tester);
      expect(find.byType(RecoveryPhraseScreen), findsOneWidget);

      router.go('/collect');
      await pumpFrames(tester);
      expect(selectedTab(tester), 1);
      expect(phrase(), findsNothing, reason: 'not kept behind a tab');
      await tapTab(tester, 'Wallet');
      expect(phrase(), findsNothing);
    });
  });

  testWidgets('Earnings keeps its list, and refetches after a minute away', (
    tester,
  ) async {
    final wallet = _CountingWallet();
    final router = await pumpApp(
      tester,
      walletRepository: wallet,
      signedIn: true,
    );
    router.go('/wallet');
    await pumpFrames(tester, frames: 8);
    final opened = wallet.transactionCalls;
    expect(opened, greaterThan(0));

    await tapTab(tester, 'Weather');
    await tapTab(tester, 'Wallet');
    expect(wallet.transactionCalls, opened, reason: 'a quick look is free');

    await tapTab(tester, 'Weather');
    now = now.add(tabDataStaleAfter);
    await tapTab(tester, 'Wallet');
    await pumpFrames(tester);
    expect(wallet.transactionCalls, opened + 1);
    tester.takeException();
  });

  testWidgets('Sky View opens over the shell and Back returns to Weather', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.push('/weather/ar');
    await pumpFrames(tester);
    expect(find.byType(BottomNavigationBar), findsNothing);
    router.pop();
    await pumpFrames(tester);
    expect(find.byType(ForecastDashboard), findsOneWidget);
    expect(weather.forecastCalls, 1);
  });
}
