import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/crypto/key_manager.dart';
import '../../../../core/errors/failures.dart';
import '../../data/models/transaction_model.dart';
import '../../data/models/transaction_page.dart';
import '../../data/repositories/wallet_repository_impl.dart';
import 'wallet_provider.dart';

final transactionsProvider =
    AsyncNotifierProvider.autoDispose<TransactionsNotifier, TransactionsState>(
      TransactionsNotifier.new,
      retry: retryUnlessDefinite,
    );

class TransactionsState {
  final List<TransactionModel> items;
  final List<TransactionModel> credits;
  final bool hasMore;
  final bool loadingMore;

  /// The node had more reward records past those it read, so this list of paid
  /// rewards may be missing some. It reads the whole chain's records a page at a
  /// time and keeps this wallet's, so this can be true even with none listed.
  final bool creditsTruncated;
  final bool historyUnavailable;

  /// False for a bounded window; null when not reported.
  final bool? complete;
  final int? windowStartHeight;

  const TransactionsState({
    required this.items,
    this.credits = const [],
    required this.hasMore,
    required this.loadingMore,
    this.creditsTruncated = false,
    this.historyUnavailable = false,
    this.complete,
    this.windowStartHeight,
  });

  static const unavailable = TransactionsState(
    items: [],
    hasMore: false,
    loadingMore: false,
    historyUnavailable: true,
  );
  static const empty = TransactionsState(
    items: [],
    hasMore: false,
    loadingMore: false,
  );

  TransactionsState copyWith({
    List<TransactionModel>? items,
    bool? hasMore,
    bool? loadingMore,
    bool? historyUnavailable,
  }) => TransactionsState(
    items: items ?? this.items,
    credits: credits,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    creditsTruncated: creditsTruncated,
    historyUnavailable: historyUnavailable ?? this.historyUnavailable,
    complete: complete,
    windowStartHeight: windowStartHeight,
  );
}

class TransactionsNotifier extends AsyncNotifier<TransactionsState> {
  /// The most the public edge admits (`limit=<1..50>`). Each read also returns
  /// this many reward records, so the larger page shows more of them.
  static const pageSize = 50;
  int _pagesLoaded = 0;
  int _generation = 0;
  bool _loadingMore = false;
  bool _refreshing = false;
  CancelToken? _cancelToken;
  Future<void> _requestTail = Future.value();

  bool _active(int generation) => ref.mounted && generation == _generation;

  int _restart() {
    _cancelToken?.cancel('History request superseded');
    _cancelToken = CancelToken();
    _pagesLoaded = 0;
    _loadingMore = false;
    return ++_generation;
  }

  @override
  Future<TransactionsState> build() async {
    final generation = _restart();
    _refreshing = false;
    ref.onDispose(() {
      ++_generation;
      _cancelToken?.cancel('History disposed');
    });
    final keyManager = ref.watch(keyManagerProvider);
    final address = await keyManager.getAddress();
    if (!_active(generation)) throw const _HistoryCancelled();
    if (address == null) return TransactionsState.empty;
    try {
      final page = await _fetchPage(address, generation, offset: 0);
      return _firstPageState(page);
    } on NotAvailableFailure {
      return TransactionsState.unavailable;
    }
  }

  TransactionsState _firstPageState(TransactionPage page) {
    _pagesLoaded = 1;
    return TransactionsState(
      items: page.items,
      credits: page.credits,
      hasMore: page.hasMore,
      loadingMore: false,
      creditsTruncated: page.creditNextCursor != null,
      complete: page.complete,
      windowStartHeight: page.windowStartHeight,
    );
  }

  /// Serialize even a refresh/rebuild behind the cancelled previous request.
  Future<TransactionPage> _fetchPage(
    String address,
    int generation, {
    required int offset,
  }) async {
    final previous = _requestTail;
    final finished = Completer<void>();
    _requestTail = finished.future;
    try {
      await previous;
      if (!_active(generation)) throw const _HistoryCancelled();
      final result = await ref
          .read(walletRepositoryProvider)
          .getTransactions(
            address,
            offset: offset,
            limit: pageSize,
            cancelToken: _cancelToken,
          );
      if (!_active(generation)) throw const _HistoryCancelled();
      return result.fold<TransactionPage>(
        (failure) => throw failure,
        (page) => page,
      );
    } finally {
      finished.complete();
    }
  }

  List<TransactionModel> _merge(
    List<TransactionModel> old,
    List<TransactionModel> page,
  ) {
    final seen = {
      for (final tx in old)
        if (tx.eventId != null || tx.hash.isNotEmpty) tx.eventId ?? tx.hash,
    };
    return [
      ...old,
      ...page.where(
        (tx) =>
            (tx.eventId == null && tx.hash.isEmpty) ||
            seen.add(tx.eventId ?? tx.hash),
      ),
    ];
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || _loadingMore || _refreshing || !current.hasMore) {
      return;
    }
    _loadingMore = true; // Lock before the asynchronous address read.
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final address = await ref.read(keyManagerProvider).getAddress();
      if (!_active(generation)) return;
      if (address == null) {
        state = AsyncData(current.copyWith(loadingMore: false));
        return;
      }
      final page = await _fetchPage(
        address,
        generation,
        offset: _pagesLoaded * pageSize,
      );
      _pagesLoaded++;
      final items = _merge(current.items, page.items);
      state = AsyncData(
        TransactionsState(
          items: items,
          // Every page repeats the same reward records, and may add a new one.
          credits: _merge(current.credits, page.credits),
          hasMore: items.length > current.items.length && page.hasMore,
          loadingMore: false,
          creditsTruncated:
              current.creditsTruncated || page.creditNextCursor != null,
          complete: page.complete ?? current.complete,
          windowStartHeight:
              page.windowStartHeight ?? current.windowStartHeight,
        ),
      );
    } on _HistoryCancelled {
      // Superseded by refresh/disposal.
    } on NotAvailableFailure {
      if (_active(generation)) {
        state = const AsyncData(TransactionsState.unavailable);
      }
    } catch (e, st) {
      if (_active(generation)) state = AsyncError(e, st);
    } finally {
      if (_active(generation)) _loadingMore = false;
    }
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final generation = _restart();
    state = const AsyncLoading();
    try {
      final address = await ref.read(keyManagerProvider).getAddress();
      if (!_active(generation)) return;
      if (address == null) {
        state = const AsyncData(TransactionsState.empty);
        return;
      }
      state = AsyncData(
        _firstPageState(await _fetchPage(address, generation, offset: 0)),
      );
    } on _HistoryCancelled {
      // Superseded/disposed.
    } on NotAvailableFailure {
      if (_active(generation)) {
        state = const AsyncData(TransactionsState.unavailable);
      }
    } catch (e, st) {
      if (_active(generation)) state = AsyncError(e, st);
    } finally {
      if (_active(generation)) _refreshing = false;
    }
  }
}

class _HistoryCancelled implements Exception {
  const _HistoryCancelled();
}
