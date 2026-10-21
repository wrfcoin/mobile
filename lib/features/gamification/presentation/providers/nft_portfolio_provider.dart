import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../data/models/weather_nft_model.dart';
import '../../data/repositories/nft_repository.dart';

class NftPortfolioState {
  const NftPortfolioState({
    this.nfts = const [],
    this.loading = false,
    this.error,
    this.claiming = false,
    this.claimError,
  });

  final List<WeatherNftModel> nfts;
  final bool loading;
  final Failure? error;
  final bool claiming;
  final Failure? claimError;

  NftPortfolioState copyWith({
    List<WeatherNftModel>? nfts,
    bool? loading,
    Failure? error,
    bool? claiming,
    Failure? claimError,
    bool clearError = false,
    bool clearClaimError = false,
  }) {
    return NftPortfolioState(
      nfts: nfts ?? this.nfts,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      claiming: claiming ?? this.claiming,
      claimError: clearClaimError ? null : (claimError ?? this.claimError),
    );
  }
}

class NftPortfolioNotifier extends Notifier<NftPortfolioState> {
  late NftRepository _repository;

  @override
  NftPortfolioState build() {
    _repository = ref.watch(nftRepositoryProvider);
    return const NftPortfolioState();
  }

  Future<void> loadPortfolio(String userId) async {
    state = state.copyWith(loading: true, clearError: true);
    final result = await _repository.getPortfolio(userId);
    if (!ref.mounted) return;
    result.fold(
      (failure) => state = state.copyWith(loading: false, error: failure),
      (nfts) => state = state.copyWith(loading: false, nfts: nfts),
    );
  }

  /// Claims [nftId] on behalf of [userId] then refreshes the portfolio.
  Future<void> claimNft(String userId, String nftId) async {
    if (state.claiming) return;
    state = state.copyWith(claiming: true, clearClaimError: true);
    final result = await _repository.claimNft(userId, nftId);
    if (!ref.mounted) return;
    result.fold(
      (failure) => state = state.copyWith(claiming: false, claimError: failure),
      (nft) {
        final updated = state.nfts
            .map((n) => n.id == nft.id ? nft : n)
            .toList();
        state = state.copyWith(claiming: false, nfts: updated);
      },
    );
  }
}

final nftPortfolioProvider =
    NotifierProvider<NftPortfolioNotifier, NftPortfolioState>(
      NftPortfolioNotifier.new,
    );
