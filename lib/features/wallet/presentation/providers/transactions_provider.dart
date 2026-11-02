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

  /// Where Load more continues reading reward records.
  final String? creditNextCursor;

  /// Still looking for this wallet's first reward. The node reads the whole
  /// chain's records a page at a time and keeps this wallet's, so a page can
  /// come back with none and still have more behind it.
  final bool discoveringCredits;

  /// The node had more reward records past those read, so this list of paid
  /// rewards may be missing some.
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
    this.creditNextCursor,
    this.discoveringCredits = false,
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
    creditNextCursor: creditNextCursor,
    discoveringCredits: discoveringCredits,
    creditsTruncated: creditsTruncated,
    historyUnavailable: historyUnavailable ?? this.historyUnavailable,
    complete: complete,
    windowStartHeight: windowStartHeight,
  );
}

extension on TransactionsState {
  /// The same list, with the search for a first reward over and Load more left
  /// to carry on from [creditNextCursor].
  TransactionsState withoutDiscovery() => TransactionsState(
    items: items,
    credits: credits,
    hasMore: hasMore,
    loadingMore: false,
    creditNextCursor: creditNextCursor,
    creditsTruncated: true,
    complete: complete,
    windowStartHeight: windowStartHeight,
  );
}

class TransactionsNotifier extends AsyncNotifier<TransactionsState> {
  /// The most the public edge admits (`limit=<1..50>`). Each read also returns
  /// this many reward records, so the larger page shows more of them.
  static const pageSize = 50;

  /// Requests spent looking for a wallet's first reward before leaving the rest
  /// to Load more. Each reads [WalletRemoteDataSource.creditPageSize] records.
  static const maxCreditDiscoveryPages = 30;

  /// The only cursor the public edge admits: a commit ID.
  static final _pageableCursor = RegExp(r'^[0-9a-f]{64}$');

  int _pagesLoaded = 0;
  int _creditPagesLoaded = 0;
  bool _transactionHasMore = false;
  final _seenCursors = <String>{};
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
    _creditPagesLoaded = 0;
    _transactionHasMore = false;
    _seenCursors.clear();
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
      final first = _firstPageState(page);
      if (first.discoveringCredits) {
        // Publish the first page before background discovery updates it.
        unawaited(Future<void>(() => _discoverCredits(address, generation)));
      }
      return first;
    } on NotAvailableFailure {
      return TransactionsState.unavailable;
    }
  }

  TransactionsState _firstPageState(TransactionPage page) {
    _pagesLoaded = 1;
    _creditPagesLoaded = 1;
    _transactionHasMore = page.hasMore;
    final cursor = _nextCursor(page);
    return TransactionsState(
      items: page.items,
      credits: page.credits,
      hasMore: page.hasMore || cursor != null,
      loadingMore: false,
      creditNextCursor: cursor,
      discoveringCredits: page.credits.isEmpty && cursor != null,
      creditsTruncated: page.creditNextCursor != null,
      complete: page.complete,
      windowStartHeight: page.windowStartHeight,
    );
  }

  /// The cursor to read next, or null when there is none or going on is
  /// pointless: one the edge would refuse, or one already read (a loop).
  String? _nextCursor(TransactionPage page) {
    final cursor = page.creditNextCursor;
    if (cursor == null || !_pageableCursor.hasMatch(cursor)) return null;
    return _seenCursors.add(cursor) ? cursor : null;
  }

  /// Serialize even a refresh/rebuild behind the cancelled previous request.
  Future<TransactionPage> _fetchPage(
    String address,
    int generation, {
    required int offset,
    String? creditAfter,
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
            creditAfter: creditAfter,
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

  /// Reads reward records until this wallet's first one turns up, keeping the
  /// transaction list where it is. A failed read ends the search and keeps what
  /// is on screen: Load more picks it up from the same place.
  Future<void> _discoverCredits(String address, int generation) async {
    while (_active(generation)) {
      final current = state.value;
      if (current == null || !current.discoveringCredits) return;
      final cursor = current.creditNextCursor;
      if (cursor == null) return;
      if (_creditPagesLoaded >= maxCreditDiscoveryPages) {
        state = AsyncData(current.withoutDiscovery());
        return;
      }
      final TransactionPage page;
      try {
        // Credit-only discovery must not advance the transaction offset.
        page = await _fetchPage(
          address,
          generation,
          offset: 0,
          creditAfter: cursor,
        );
      } on _HistoryCancelled {
        return;
      } catch (_) {
        if (_active(generation)) state = AsyncData(current.withoutDiscovery());
        return;
      }
      if (!_active(generation)) return;
      _creditPagesLoaded++;
      final next = _nextCursor(page);
      final credits = _merge(current.credits, page.credits);
      state = AsyncData(
        TransactionsState(
          items: current.items,
          credits: credits,
          hasMore: _transactionHasMore || next != null,
          loadingMore: false,
          creditNextCursor: next,
          discoveringCredits: credits.isEmpty && next != null,
          creditsTruncated: page.creditNextCursor != null,
          complete: page.complete ?? current.complete,
          windowStartHeight:
              page.windowStartHeight ?? current.windowStartHeight,
        ),
      );
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
    if (current == null ||
        _loadingMore ||
        _refreshing ||
        current.discoveringCredits ||
        !current.hasMore) {
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
        creditAfter: current.creditNextCursor,
      );
      _pagesLoaded++;
      final items = _merge(current.items, page.items);
      _transactionHasMore = items.length > current.items.length && page.hasMore;
      // With no cursor the reads repeat the first reward records, so there is
      // nothing new in them. A read that ends the cursor clears the notice.
      final paging = current.creditNextCursor != null;
      final next = paging ? _nextCursor(page) : null;
      state = AsyncData(
        TransactionsState(
          items: items,
          credits: paging
              ? _merge(current.credits, page.credits)
              : current.credits,
          hasMore: _transactionHasMore || next != null,
          loadingMore: false,
          creditNextCursor: next,
          creditsTruncated: paging
              ? page.creditNextCursor != null
              : current.creditsTruncated,
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
      await _discoverCredits(address, generation);
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
