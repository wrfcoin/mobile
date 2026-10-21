import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_handoff.dart';
import '../../../../core/errors/failures.dart';
import '../../data/models/wallet_model.dart';
import '../../data/repositories/wallet_repository_impl.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/crypto/signed_transfer.dart';
import '../../../../services/api/api_client.dart';

final walletProvider = AsyncNotifierProvider<WalletNotifier, WalletModel?>(
  WalletNotifier.new,
  retry: retryUnlessDefinite,
);

/// Riverpod retries a failed provider about ten times over ~40 s, showing
/// "Loading" all the while. That suits a transient failure (a 5xx, a
/// dropped connection, a timeout), but a definite answer does not change
/// on retry: it only repeats the wallet request and hides the answer
/// (mobile#320). No retry for:
/// - a 401 (no session);
/// - "not available" (501, or a 503 with no core4 Reader credential);
/// - any other 4xx, such as a 403 refused session or a 404, except 408
///   (request timeout) and 429 (rate limited), which may pass later.
Duration? retryUnlessDefinite(int retryCount, Object error) {
  if (error is AuthFailure || error is NotAvailableFailure) return null;
  if (error is Failure) {
    final status = error.statusCode;
    if (status != null &&
        status >= 400 &&
        status < 500 &&
        status != 408 &&
        status != 429) {
      return null;
    }
  }
  return ProviderContainer.defaultRetry(retryCount, error);
}

class WalletNotifier extends AsyncNotifier<WalletModel?> {
  @override
  Future<WalletModel?> build() async {
    final keyManager = ref.watch(keyManagerProvider);
    final address = await keyManager.getAddress();
    if (address == null) return null;
    await ref.read(apiClientProvider).ensureWalletSession();
    if (ref.read(authHandoffControllerProvider).requiresWalletConnect) {
      return null;
    }
    return _fetchWallet(address);
  }

  Future<WalletModel?> _fetchWallet(String address) async {
    final repo = ref.read(walletRepositoryProvider);
    final result = await repo.getWallet(address);
    return result.fold((failure) => throw failure, (wallet) => wallet);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final keyManager = ref.read(keyManagerProvider);
      final address = await keyManager.getAddress();
      if (address == null) return null;
      await ref.read(apiClientProvider).ensureWalletSession();
      if (ref.read(authHandoffControllerProvider).requiresWalletConnect) {
        return null;
      }
      return _fetchWallet(address);
    });
  }

  /// Signs and submits a transparent transfer of [amountBaseUnits] (an
  /// integer base-unit string) with the wallet's ed25519 [signer].
  Future<Map<String, dynamic>> sendTransaction({
    required String from,
    required String to,
    required String amountBaseUnits,
    required Ed25519TransferSigner signer,
  }) async {
    final repo = ref.read(walletRepositoryProvider);
    final result = await repo.sendTransaction(
      from: from,
      to: to,
      amountBaseUnits: amountBaseUnits,
      signer: signer,
    );

    // Preserve the submission response. Refresh reads must not hide its
    // identifier or turn an accepted submission into an apparent failure.
    return result.fold((failure) => throw failure, (receipt) => receipt);
  }

  /// Resolves a stealth address for [recipientAddress] then submits a private
  /// transaction through the backend privacy pipeline.
  Future<void> sendPrivateTransaction({
    required String from,
    required String recipientAddress,
    required String amount,
    required String privacyLevel,
    String? memo,
  }) async {
    final repo = ref.read(walletRepositoryProvider);

    final stealthResult = await repo.generateStealthAddress(recipientAddress);
    final stealthAddress = stealthResult.fold(
      (failure) => throw failure,
      (addr) => addr,
    );

    final result = await repo.sendPrivateTransaction(
      from: from,
      to: stealthAddress,
      amount: amount,
      privacyLevel: privacyLevel,
      memo: memo,
    );

    result.fold((failure) => throw failure, (_) => refresh());
  }
}
