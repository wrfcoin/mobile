import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_handoff.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../data/explorer_models.dart';
import '../../data/explorer_remote_datasource.dart';

/// The poll interval. The backend caches the summary for at least 10 s, so
/// polling faster only re-reads the same answer; the screen enforces the floor.
final chainPollIntervalProvider = Provider<Duration>(
  (_) => const Duration(seconds: 15),
);

const Duration chainPollFloor = Duration(seconds: 10);

/// Owns the [CancelToken] every Chain read carries, so the page can cancel
/// in-flight requests AND their pending retries (the token rides on the
/// request options the retry interceptor re-sends) when it goes to the
/// background, is covered by another page, or is disposed.
class ChainReadScope {
  CancelToken _token = CancelToken();
  final Set<CancelToken> _details = <CancelToken>{};

  CancelToken get token => _token;

  /// Cancels everything in flight and starts a fresh token for later reads.
  void cancelAndRenew() {
    if (!_token.isCancelled) _token.cancel('chain page not visible');
    _token = CancelToken();
  }

  /// A token for one block-detail read, tied to the page lifecycle: it is cancelled on
  /// background and on leaving the page ([cancelDetails], [release]), and by the caller
  /// when the sheet closes ([closeDetail]). A detail read is NOT cancelled merely because
  /// the sheet covers the page.
  CancelToken newDetailToken() {
    final token = CancelToken();
    _details.add(token);
    return token;
  }

  void closeDetail(CancelToken token) {
    if (!token.isCancelled) token.cancel('block detail closed');
    _details.remove(token);
  }

  void cancelDetails() {
    for (final token in _details) {
      if (!token.isCancelled) token.cancel('chain page not visible');
    }
    _details.clear();
  }

  /// A screen instance is leaving: cancel everything it started (list reads, retries and
  /// detail reads) and leave the scope usable, so the next visit reads afresh.
  void release() {
    cancelDetails();
    cancelAndRenew();
  }

  /// The container is going away.
  void dispose() {
    cancelDetails();
    if (!_token.isCancelled) _token.cancel('chain page disposed');
  }
}

final chainReadScopeProvider = Provider<ChainReadScope>((ref) {
  final scope = ChainReadScope();
  ref.onDispose(scope.dispose);
  return scope;
});

/// Whether the private My account card may show: a CURRENT session, not a
/// cached wallet. It is false after sign-out, session expiry or rejection
/// (the handoff says so) or when no access token is stored. It only reads
/// storage; it never starts a login, prompts, or sends a request.
final chainAccountVisibleProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final handoff = ref.watch(authHandoffControllerProvider);
  if (handoff.requiresWalletConnect) return false;
  final keys = ref.watch(keyManagerProvider);
  return (await keys.getAuthToken()) != null;
});

/// Summary plus the recent blocks. Neither read throws, so a failure is shown
/// as degraded / unavailable instead of an error screen. A read that was
/// cancelled (page hidden, covered or disposed) is discarded, never shown.
class ChainSnapshotNotifier extends AsyncNotifier<ChainSnapshot> {
  @override
  Future<ChainSnapshot> build() async {
    final snapshot = await _load(ref.read(chainReadScopeProvider).token);
    return snapshot ??
        const ChainSnapshot(summary: ExplorerSummary.degraded(), blocks: null);
  }

  /// Re-reads; keeps the current data when the read is cancelled.
  Future<void> refresh() async {
    final scope = ref.read(chainReadScopeProvider);
    final token = scope.token;
    final snapshot = await _load(token);
    if (snapshot == null || !ref.mounted) return;
    state = AsyncData(snapshot);
  }

  /// null when [token] was cancelled before the reads finished.
  Future<ChainSnapshot?> _load(CancelToken token) async {
    final source = ref.read(explorerRemoteDataSourceProvider);
    final results = await Future.wait<Object?>([
      source.fetchSummary(cancelToken: token),
      source.fetchRecentBlocks(cancelToken: token),
    ]);
    if (token.isCancelled) return null;
    return ChainSnapshot(
      summary: results[0]! as ExplorerSummary,
      blocks: results[1] as List<ChainBlock>?,
    );
  }
}

final chainSnapshotProvider =
    AsyncNotifierProvider.autoDispose<ChainSnapshotNotifier, ChainSnapshot>(
      ChainSnapshotNotifier.new,
    );
