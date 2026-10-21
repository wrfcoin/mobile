import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/app_localizations.dart';
import 'core/preferences/app_preferences.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/collector/presentation/providers/collector_provider.dart';
import 'features/onboarding/presentation/providers/onboarding_controller.dart';
import 'features/weather/presentation/providers/alert_settings_provider.dart';

class WrfcoinApp extends ConsumerStatefulWidget {
  const WrfcoinApp({super.key});

  @override
  ConsumerState<WrfcoinApp> createState() => _WrfcoinAppState();
}

class _WrfcoinAppState extends ConsumerState<WrfcoinApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(alertSettingsProvider);
      ref.read(appPreferencesProvider);
      ref.read(onboardingControllerProvider);
      if (!kIsWeb) {
        ref.read(collectorProvider.notifier);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed) {
      unawaited(ref.read(collectorProvider.notifier).handleAppResume());
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final appPreferences = ref.watch(appPreferencesProvider).preferences;
    final onboardingState = ref.watch(onboardingControllerProvider);

    if (!onboardingState.loaded) {
      return MaterialApp(
        title: 'WRFCoin',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: appPreferences.themeMode,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: MaterialApp.router(
        title: 'WRFCoin',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: appPreferences.themeMode,
        locale: appPreferences.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
