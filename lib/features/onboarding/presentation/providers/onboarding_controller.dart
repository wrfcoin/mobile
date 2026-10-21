import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingState {
  final bool loaded;
  final bool completed;
  final bool dismissedForSession;

  const OnboardingState({
    this.loaded = false,
    this.completed = false,
    this.dismissedForSession = false,
  });

  bool get shouldShowTour => loaded && !completed && !dismissedForSession;

  OnboardingState copyWith({
    bool? loaded,
    bool? completed,
    bool? dismissedForSession,
  }) {
    return OnboardingState(
      loaded: loaded ?? this.loaded,
      completed: completed ?? this.completed,
      dismissedForSession: dismissedForSession ?? this.dismissedForSession,
    );
  }
}

final onboardingStoreProvider = Provider<OnboardingStore>((ref) {
  return const OnboardingStore();
});

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

class OnboardingController extends Notifier<OnboardingState> {
  late OnboardingStore _store;

  @override
  OnboardingState build() {
    _store = ref.watch(onboardingStoreProvider);
    Future.microtask(load);
    return const OnboardingState();
  }

  Future<void> load() async {
    final completed = await _store.loadCompleted();
    state = state.copyWith(
      loaded: true,
      completed: completed,
      dismissedForSession: false,
    );
  }

  Future<void> finish({required bool dontShowAgain}) async {
    state = state.copyWith(
      loaded: true,
      completed: dontShowAgain,
      dismissedForSession: true,
    );
    await _store.saveCompleted(dontShowAgain);
  }

  Future<void> restart() async {
    state = state.copyWith(
      loaded: true,
      completed: false,
      dismissedForSession: false,
    );
    await _store.saveCompleted(false);
  }
}

class OnboardingStore {
  const OnboardingStore();

  static const _completedKey = 'onboarding.completed';

  Future<bool> loadCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  Future<void> saveCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, completed);
  }
}
