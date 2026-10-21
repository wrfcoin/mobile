import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/models/faucet_models.dart';
import '../../data/repositories/faucet_repository.dart';

/// Immutable view-state for the faucet screen.
class FaucetState {
  /// The wallet address tokens will be dispensed to (masked in the UI).
  final String? walletAddress;

  /// The active math-captcha challenge, if one has been requested.
  final FaucetChallenge? challenge;

  /// True while a challenge request is in flight.
  final bool loadingChallenge;

  /// True while a claim is in flight.
  final bool claiming;

  /// Set when the most recent claim succeeded.
  final FaucetClaimResult? result;

  /// Set when the most recent action failed (challenge or claim).
  final Failure? error;

  const FaucetState({
    this.walletAddress,
    this.challenge,
    this.loadingChallenge = false,
    this.claiming = false,
    this.result,
    this.error,
  });

  bool get hasWallet => walletAddress != null && walletAddress!.isNotEmpty;
  bool get hasChallenge => challenge != null;
  bool get isBusy => loadingChallenge || claiming;

  FaucetState copyWith({
    String? walletAddress,
    FaucetChallenge? challenge,
    bool? loadingChallenge,
    bool? claiming,
    FaucetClaimResult? result,
    Failure? error,
    bool clearChallenge = false,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return FaucetState(
      walletAddress: walletAddress ?? this.walletAddress,
      challenge: clearChallenge ? null : (challenge ?? this.challenge),
      loadingChallenge: loadingChallenge ?? this.loadingChallenge,
      claiming: claiming ?? this.claiming,
      result: clearResult ? null : (result ?? this.result),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final faucetProvider = NotifierProvider<FaucetNotifier, FaucetState>(
  FaucetNotifier.new,
);

/// Drives the faucet onboarding flow: load wallet address → request captcha →
/// submit answer → surface dispense result or backend error.
class FaucetNotifier extends Notifier<FaucetState> {
  @override
  FaucetState build() {
    // Resolve the active wallet address asynchronously after first build.
    _loadWalletAddress();
    return const FaucetState();
  }

  Future<void> _loadWalletAddress() async {
    final address = await ref.read(keyManagerProvider).getAddress();
    state = state.copyWith(walletAddress: address);
  }

  /// Requests a fresh math-captcha challenge from the backend.
  Future<void> requestChallenge() async {
    if (state.loadingChallenge) return;
    state = state.copyWith(
      loadingChallenge: true,
      clearError: true,
      clearResult: true,
      clearChallenge: true,
    );

    final result = await ref.read(faucetRepositoryProvider).requestChallenge();
    state = result.fold(
      (failure) => state.copyWith(loadingChallenge: false, error: failure),
      (challenge) =>
          state.copyWith(loadingChallenge: false, challenge: challenge),
    );
  }

  /// Submits the user's [answer] for the active challenge and requests tokens.
  ///
  /// On a failed captcha the backend invalidates the challenge, so callers
  /// must request a fresh one; this notifier clears the stale challenge on
  /// any failure so the UI prompts for a new captcha.
  Future<void> claim(String rawAnswer) async {
    if (state.claiming) return;

    final address = state.walletAddress;
    if (address == null || address.isEmpty) {
      state = state.copyWith(
        error: const AuthFailure(
          'Create or import a wallet before requesting testnet tokens.',
        ),
      );
      return;
    }

    final challenge = state.challenge;
    if (challenge == null) {
      state = state.copyWith(
        error: const ValidationFailure(
          'Request a captcha challenge before claiming.',
        ),
      );
      return;
    }

    final answer = int.tryParse(rawAnswer.trim());
    if (answer == null) {
      state = state.copyWith(
        error: const ValidationFailure('Enter a numeric answer to continue.'),
      );
      return;
    }

    state = state.copyWith(claiming: true, clearError: true, clearResult: true);

    final result = await ref
        .read(faucetRepositoryProvider)
        .claim(
          walletAddress: address,
          challengeId: challenge.challengeId,
          answer: answer,
        );

    state = result.fold(
      // Challenge is single-use server-side; drop it so the UI re-requests.
      (failure) =>
          state.copyWith(claiming: false, error: failure, clearChallenge: true),
      (claimResult) => state.copyWith(
        claiming: false,
        result: claimResult,
        clearChallenge: true,
      ),
    );
  }

  /// Clears the last result/error so the user can request again.
  void reset() {
    state = state.copyWith(
      clearResult: true,
      clearError: true,
      clearChallenge: true,
    );
  }
}
