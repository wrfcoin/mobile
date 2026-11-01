import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime feature flags.  Defaults are selected per feature and
/// can be toggled via [FeatureFlagsNotifier] (useful for QA / staged rollout).
///
/// Persisted via SharedPreferences so they survive app restarts.  Override
/// with [featureFlagsProvider.overrideWithValue] in tests.
class FeatureFlags {
  const FeatureFlags({
    this.enableLocalCommunities = false,
    this.enableOnboardingTour = false,
    this.enableOfflineBuffer = true,
    this.enableAnalyticsDashboard = false,
    this.enableI18n = false,
    this.enablePwsAutoDiscovery = false,
    this.enableConnectivityHardening = false,
    this.enableAchievementsUi = true,
    this.enableFirstRunWelcome = false,
    this.enableNftPortfolio = false,
    this.enableCarbonLottery = false,
    this.enableMultiWallet = false,
    this.enableFriendChallenges = true,
  });

  /// Weather station clusters, group challenges, and neighbourhood chat.
  /// Dark-launched in R60; backend wiring is a future round.
  final bool enableLocalCommunities;

  /// First-run onboarding tour (Welcome, Station Setup, First Submission).
  /// Dark-launched; no nav wiring to main app flow.
  final bool enableOnboardingTour;

  /// Offline-first data buffering for weather submissions.
  /// Enabled by default (core reliability feature).
  final bool enableOfflineBuffer;

  /// Personal weather analytics: data export, collection heatmaps, earning
  /// trends.  Dark-launched in R63f; toggled via QA settings or staged rollout.
  final bool enableAnalyticsDashboard;

  /// ARB-based internationalization with English and Spanish support.
  /// Dark-launched; no UI for locale switching yet.
  final bool enableI18n;

  /// Ambient account station onboarding (default off). Devices are enumerated
  /// through the authenticated backend and require explicit registration.
  /// LAN/Ecowitt/Davis discovery and BLE are not enabled by this flag.
  final bool enablePwsAutoDiscovery;

  /// Adds idempotency keys to oracle POST requests so retries on flaky
  /// connections cannot create duplicate readings on the backend.
  /// Dark-launched in R75; backend validates X-Idempotency-Key header.
  final bool enableConnectivityHardening;

  /// Profile tab, enabled by default with the live earnings leaderboard.
  /// Achievements remain unavailable until backend storage is wired.
  final bool enableAchievementsUi;

  /// First-run welcome flow: 3-slide intro + inline wallet creation +
  /// permission pre-prompts.  Distinct from [enableOnboardingTour] (which
  /// is an interactive tour shown *after* the user is in the app).
  /// Dark-launched; router redirects to `/welcome` on first launch when on.
  final bool enableFirstRunWelcome;

  /// Weather NFT portfolio section in the Profile tab (streak + storm-chaser
  /// badges). Dark-launched in R83; backend endpoint is /nft/portfolio/:userId.
  final bool enableNftPortfolio;

  /// Carbon Lottery deposit/withdraw (wallet tab entry + /wallet/lottery).
  /// Dark-launched (mobile#268): no backend implements /carbon-lottery yet,
  /// so every request would fail. Flip on only for QA against a real backend.
  final bool enableCarbonLottery;

  /// Multi-wallet vault (mobile#8, PR 1). With it on, startup copies the
  /// single-slot wallet into the vault (copy-verify-then-commit) and keeps the
  /// legacy slots; `KeyManager` still reads the legacy slots. No UI yet.
  final bool enableMultiWallet;

  /// Friend Challenges (mobile#260, backend#249): the screen talks to the
  /// backend `/api/challenges` service (create, join by invite code, counts
  /// from chain readings, points only). Default on: the service is live on
  /// the public testnet. Turned off, the screen shows the honest
  /// "unavailable" state and makes no request.
  final bool enableFriendChallenges;

  FeatureFlags copyWith({
    bool? enableLocalCommunities,
    bool? enableOnboardingTour,
    bool? enableOfflineBuffer,
    bool? enableAnalyticsDashboard,
    bool? enableI18n,
    bool? enablePwsAutoDiscovery,
    bool? enableConnectivityHardening,
    bool? enableAchievementsUi,
    bool? enableFirstRunWelcome,
    bool? enableNftPortfolio,
    bool? enableCarbonLottery,
    bool? enableMultiWallet,
    bool? enableFriendChallenges,
  }) {
    return FeatureFlags(
      enableLocalCommunities:
          enableLocalCommunities ?? this.enableLocalCommunities,
      enableOnboardingTour: enableOnboardingTour ?? this.enableOnboardingTour,
      enableOfflineBuffer: enableOfflineBuffer ?? this.enableOfflineBuffer,
      enableAnalyticsDashboard:
          enableAnalyticsDashboard ?? this.enableAnalyticsDashboard,
      enableI18n: enableI18n ?? this.enableI18n,
      enablePwsAutoDiscovery:
          enablePwsAutoDiscovery ?? this.enablePwsAutoDiscovery,
      enableConnectivityHardening:
          enableConnectivityHardening ?? this.enableConnectivityHardening,
      enableAchievementsUi: enableAchievementsUi ?? this.enableAchievementsUi,
      enableFirstRunWelcome:
          enableFirstRunWelcome ?? this.enableFirstRunWelcome,
      enableNftPortfolio: enableNftPortfolio ?? this.enableNftPortfolio,
      enableCarbonLottery: enableCarbonLottery ?? this.enableCarbonLottery,
      enableMultiWallet: enableMultiWallet ?? this.enableMultiWallet,
      enableFriendChallenges:
          enableFriendChallenges ?? this.enableFriendChallenges,
    );
  }
}

class FeatureFlagsNotifier extends Notifier<FeatureFlags> {
  late SharedPreferences _prefs;

  static const _keyLocalCommunities = 'ff_enableLocalCommunities';
  static const _keyOnboardingTour = 'ff_enableOnboardingTour';
  static const _keyOfflineBuffer = 'ff_enableOfflineBuffer';
  static const _keyAnalyticsDashboard = 'ff_enableAnalyticsDashboard';
  static const _keyI18n = 'ff_enableI18n';
  static const _keyPwsAutoDiscovery = 'ff_enablePwsAutoDiscovery';
  static const _keyConnectivityHardening = 'ff_enableConnectivityHardening';
  static const _keyAchievementsUi = 'ff_enableAchievementsUi';
  static const _keyFirstRunWelcome = 'ff_enableFirstRunWelcome';
  static const _keyNftPortfolio = 'ff_enableNftPortfolio';
  static const _keyCarbonLottery = 'ff_enableCarbonLottery';
  static const _keyMultiWallet = 'ff_enableMultiWallet';
  static const _keyFriendChallenges = 'ff_enableFriendChallenges';

  @override
  FeatureFlags build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _loadFlags();
  }

  FeatureFlags _loadFlags() {
    return FeatureFlags(
      enableLocalCommunities: _prefs.getBool(_keyLocalCommunities) ?? false,
      enableOnboardingTour: _prefs.getBool(_keyOnboardingTour) ?? false,
      enableOfflineBuffer: _prefs.getBool(_keyOfflineBuffer) ?? true,
      enableAnalyticsDashboard: _prefs.getBool(_keyAnalyticsDashboard) ?? false,
      enableI18n: _prefs.getBool(_keyI18n) ?? false,
      enablePwsAutoDiscovery: _prefs.getBool(_keyPwsAutoDiscovery) ?? false,
      enableConnectivityHardening:
          _prefs.getBool(_keyConnectivityHardening) ?? false,
      enableAchievementsUi: _prefs.getBool(_keyAchievementsUi) ?? true,
      enableFirstRunWelcome: _prefs.getBool(_keyFirstRunWelcome) ?? false,
      enableNftPortfolio: _prefs.getBool(_keyNftPortfolio) ?? false,
      enableCarbonLottery: _prefs.getBool(_keyCarbonLottery) ?? false,
      enableMultiWallet: _prefs.getBool(_keyMultiWallet) ?? false,
      enableFriendChallenges: _prefs.getBool(_keyFriendChallenges) ?? true,
    );
  }

  Future<void> setLocalCommunities({required bool enabled}) async {
    await _prefs.setBool(_keyLocalCommunities, enabled);
    state = state.copyWith(enableLocalCommunities: enabled);
  }

  Future<void> setOnboardingTour({required bool enabled}) async {
    await _prefs.setBool(_keyOnboardingTour, enabled);
    state = state.copyWith(enableOnboardingTour: enabled);
  }

  Future<void> setOfflineBuffer({required bool enabled}) async {
    await _prefs.setBool(_keyOfflineBuffer, enabled);
    state = state.copyWith(enableOfflineBuffer: enabled);
  }

  Future<void> setAnalyticsDashboard({required bool enabled}) async {
    await _prefs.setBool(_keyAnalyticsDashboard, enabled);
    state = state.copyWith(enableAnalyticsDashboard: enabled);
  }

  Future<void> setI18n({required bool enabled}) async {
    await _prefs.setBool(_keyI18n, enabled);
    state = state.copyWith(enableI18n: enabled);
  }

  Future<void> setPwsAutoDiscovery({required bool enabled}) async {
    await _prefs.setBool(_keyPwsAutoDiscovery, enabled);
    state = state.copyWith(enablePwsAutoDiscovery: enabled);
  }

  Future<void> setConnectivityHardening({required bool enabled}) async {
    await _prefs.setBool(_keyConnectivityHardening, enabled);
    state = state.copyWith(enableConnectivityHardening: enabled);
  }

  Future<void> setAchievementsUi({required bool enabled}) async {
    await _prefs.setBool(_keyAchievementsUi, enabled);
    state = state.copyWith(enableAchievementsUi: enabled);
  }

  Future<void> setFirstRunWelcome({required bool enabled}) async {
    await _prefs.setBool(_keyFirstRunWelcome, enabled);
    state = state.copyWith(enableFirstRunWelcome: enabled);
  }

  Future<void> setNftPortfolio({required bool enabled}) async {
    await _prefs.setBool(_keyNftPortfolio, enabled);
    state = state.copyWith(enableNftPortfolio: enabled);
  }

  Future<void> setCarbonLottery({required bool enabled}) async {
    await _prefs.setBool(_keyCarbonLottery, enabled);
    state = state.copyWith(enableCarbonLottery: enabled);
  }

  Future<void> setMultiWallet({required bool enabled}) async {
    await _prefs.setBool(_keyMultiWallet, enabled);
    state = state.copyWith(enableMultiWallet: enabled);
  }

  Future<void> setFriendChallenges({required bool enabled}) async {
    await _prefs.setBool(_keyFriendChallenges, enabled);
    state = state.copyWith(enableFriendChallenges: enabled);
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'Override sharedPreferencesProvider in ProviderScope',
  );
});

final featureFlagsProvider =
    NotifierProvider<FeatureFlagsNotifier, FeatureFlags>(
      FeatureFlagsNotifier.new,
    );
