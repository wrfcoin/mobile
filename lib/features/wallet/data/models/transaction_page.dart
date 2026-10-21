import 'transaction_model.dart';

/// One page of wallet history as the backend reported it
/// (`GET /wallet/:address/transactions`, backend#1199).
///
/// The core4-backed history is a bounded window, not the full chain history:
/// the backend always sends `complete: false` and the first block height the
/// window covers in `windowStartHeight`. Those are carried here rather than
/// dropped so the screen can say what it is actually showing.
class TransactionPage {
  final List<TransactionModel> items;

  /// Paid ledger events have no settlement time and are paged separately.
  final List<TransactionModel> credits;
  final String? creditNextCursor;

  /// `false` when the backend says the window is partial; null when the
  /// response did not say.
  final bool? complete;

  /// First block height covered by the window, when reported.
  final int? windowStartHeight;

  /// Number of transactions in the window, when reported.
  final int? totalInWindow;

  final int offset;
  final int limit;

  const TransactionPage({
    required this.items,
    this.credits = const [],
    this.creditNextCursor,
    required this.offset,
    required this.limit,
    this.complete,
    this.windowStartHeight,
    this.totalInWindow,
  });

  /// Whether another page exists after this one.
  ///
  /// Uses `totalInWindow` when the backend reports it, and otherwise treats a
  /// short page as the last one.
  bool get hasMore {
    if (items.isEmpty) return false;
    final total = totalInWindow;
    if (total != null) return offset + items.length < total;
    return items.length >= limit;
  }
}
