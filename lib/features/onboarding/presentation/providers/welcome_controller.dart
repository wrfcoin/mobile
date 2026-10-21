import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent state for the first-run welcome flow (issue #159).
///
/// `seenWelcome=true` means the user has completed or skipped the flow at
/// least once; subsequent launches should not redirect back to `/welcome`.
/// Distinct from [OnboardingController] which tracks the interactive in-app
/// tour from issue #74.
class WelcomeState {
  final bool loaded;
  final bool seenWelcome;

  const WelcomeState({this.loaded = false, this.seenWelcome = false});

  /// True only when the controller has finished reading SharedPreferences and
  /// the user has not yet completed the flow.  Router redirect logic must
  /// wait for [loaded] before deciding whether to send the user to `/welcome`.
  bool get shouldShowWelcome => loaded && !seenWelcome;

  WelcomeState copyWith({bool? loaded, bool? seenWelcome}) {
    return WelcomeState(
      loaded: loaded ?? this.loaded,
      seenWelcome: seenWelcome ?? this.seenWelcome,
    );
  }
}

final welcomeStoreProvider = Provider<WelcomeStore>((ref) {
  return const WelcomeStore();
});

final welcomeControllerProvider =
    NotifierProvider<WelcomeController, WelcomeState>(WelcomeController.new);

class WelcomeController extends Notifier<WelcomeState> {
  late WelcomeStore _store;
  Future<void>? _inFlightLoad;

  @override
  WelcomeState build() {
    _store = ref.watch(welcomeStoreProvider);
    _inFlightLoad = load();
    return const WelcomeState();
  }

  /// Awaits any auto-load in flight then re-reads the store so callers can
  /// safely mutate persistent state without racing with the constructor's
  /// background load.
  Future<void> load() async {
    await _inFlightLoad;
    final seen = await _store.loadSeen();
    state = state.copyWith(loaded: true, seenWelcome: seen);
    _inFlightLoad = null;
  }

  Future<void> complete() async {
    // Ensure any auto-load from the constructor has fully settled before we
    // flip the flag — otherwise the late load() can overwrite our mutation.
    await _inFlightLoad;
    await _store.saveSeen(true);
    state = state.copyWith(loaded: true, seenWelcome: true);
  }

  /// Reset for QA — re-arms the first-run flow on next launch.
  Future<void> reset() async {
    await _inFlightLoad;
    await _store.saveSeen(false);
    state = state.copyWith(loaded: true, seenWelcome: false);
  }
}

class WelcomeStore {
  const WelcomeStore();

  static const _seenKey = 'welcome.seen';

  Future<bool> loadSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey) ?? false;
  }

  Future<void> saveSeen(bool seen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, seen);
  }
}
