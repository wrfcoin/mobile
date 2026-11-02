import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../services/crypto/key_manager.dart';
import '../../../../services/crypto/wallet_secure_storage.dart';
import '../../data/models/pending_send.dart';
import '../../data/repositories/wallet_repository_impl.dart';
import 'transactions_provider.dart';
import 'wallet_provider.dart';

/// How long Send stays blocked with no answer from the chain. A little longer
/// than core4's 10-minute replay window (PERMISSIONLESS_REPLAY_TTL_SECS), during
/// which the backend answers 409 to the same nonce anyway, so waiting less would
/// only swap this message for that one. After it, the row says plainly that
/// there's no answer, and the user decides. It's a device clock, so a wrong one
/// can only end the block early, where the 409 is still the backstop.
const pendingSendTimeLimit = Duration(minutes: 11);

/// Chain 888 makes a block about every 77 s, so this catches one soon after.
const pendingSendPollInterval = Duration(seconds: 30);

final pendingSendClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

final pendingSendProvider =
    NotifierProvider<PendingSendNotifier, PendingSendState>(
      PendingSendNotifier.new,
    );

class PendingSendState {
  const PendingSendState({
    this.send,
    this.overdue = false,
    this.checkFailed = false,
    this.checking = false,
  });

  final PendingSend? send;

  /// Past [pendingSendTimeLimit] with no answer from the chain.
  final bool overdue;

  /// The last status read failed, so the row can't say where the send stands.
  final bool checkFailed;
  final bool checking;

  /// Whether a new send must wait. Always ends by the time limit, whatever the
  /// network does. While reads are failing a send couldn't get a nonce anyway.
  bool get blocksSend => send != null && send!.phase.awaitingChain && !overdue;

  PendingSendState copyWith({
    bool? overdue,
    bool? checkFailed,
    bool? checking,
  }) => PendingSendState(
    send: send,
    overdue: overdue ?? this.overdue,
    checkFailed: checkFailed ?? this.checkFailed,
    checking: checking ?? this.checking,
  );
}

/// True when the backend definitely did not accept the send: an answer that
/// refuses it. A timeout, a lost connection or a 5xx proves nothing, so the send
/// is kept and followed on the chain.
bool sendDefinitelyRefused(Object error) {
  if (error is! Failure) return false;
  if (error is AuthFailure ||
      error is NotAvailableFailure ||
      error is ValidationFailure ||
      error is SecurityFailure) {
    return true;
  }
  final status = error.statusCode;
  return status != null && status >= 400 && status < 500 && status != 408;
}

class PendingSendNotifier extends Notifier<PendingSendState> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  Completer<void> _loaded = Completer<void>();
  PendingSend? _replaced;
  Future<void>? _inFlight;

  /// Completes once the saved send, if any, is loaded.
  Future<void> get ready => _loaded.future;

  @override
  PendingSendState build() {
    _loaded = Completer<void>();
    _replaced = null;
    _inFlight = null;
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _lifecycle?.dispose();
    });
    unawaited(_load());
    return const PendingSendState();
  }

  Future<void> _load() async {
    final loaded = _loaded;
    PendingSend? saved;
    try {
      saved = PendingSend.decode(
        await ref.read(walletSecureStorageProvider).getPendingSend(),
      );
      if (saved != null && !await _belongsToThisWallet(saved)) {
        await ref.read(walletSecureStorageProvider).savePendingSend(null);
        saved = null;
      }
    } catch (_) {
      // Unreadable storage must never block Send.
      saved = null;
    }
    if (!ref.mounted) return;
    if (saved != null) {
      state = PendingSendState(send: saved, overdue: _isOverdue(saved));
      _schedule();
      unawaited(check());
    }
    if (!loaded.isCompleted) loaded.complete();
  }

  Future<bool> _belongsToThisWallet(PendingSend send) async {
    final address = await ref.read(keyManagerProvider).getAddress();
    return address != null && address.toLowerCase() == send.from.toLowerCase();
  }

  bool _isOverdue(PendingSend send) {
    if (!send.phase.awaitingChain) return false;
    final elapsed = ref
        .read(pendingSendClockProvider)()
        .difference(send.submittedAt);
    // A send "from the future" means the clock moved: never wait on that.
    return elapsed.isNegative || elapsed >= pendingSendTimeLimit;
  }

  /// Called with the signed nonce right before the post, so a send whose answer
  /// is lost, or an app killed mid-post, still leaves a record.
  Future<void> begin({
    required String from,
    required String to,
    required String amountBaseUnits,
    required String nonce,
  }) async {
    await ready;
    _replaced = state.send;
    _timer?.cancel();
    await _publish(
      PendingSend(
        from: from,
        to: to,
        amountBaseUnits: amountBaseUnits,
        nonce: nonce,
        submittedAt: ref.read(pendingSendClockProvider)(),
        phase: PendingSendPhase.sending,
      ),
    );
  }

  Future<void> markSubmitted(String? hash) async {
    final send = state.send;
    if (send == null) return;
    await _publish(
      send.copyWith(phase: PendingSendPhase.submitted, hash: hash),
    );
  }

  /// The post failed. A definite refusal never entered the mempool, so the row
  /// goes back to what it showed before this attempt. Anything else stays, in
  /// the words of what it is: unknown.
  Future<void> markFailed(Object error) async {
    final send = state.send;
    if (send == null) return;
    if (sendDefinitelyRefused(error)) {
      await _publish(_replaced);
    } else {
      await _publish(send.copyWith(phase: PendingSendPhase.outcomeUnknown));
    }
  }

  /// Removes a settled or overdue row. A send still waiting can't be dismissed.
  Future<void> dismiss() async {
    if (state.blocksSend) return;
    await _publish(null);
  }

  /// Asks the chain. Safe to call at any time; it never throws, and a call while
  /// a read is running waits for that read.
  Future<void> check() async {
    await ready;
    if (!ref.mounted) return;
    // Before the guard: a read that hangs must not hold the time limit back.
    final current = state.send;
    if (current != null && !state.overdue && _isOverdue(current)) {
      state = state.copyWith(overdue: true);
      _schedule();
    }
    return _inFlight ??= _read().whenComplete(() => _inFlight = null);
  }

  Future<void> _read() async {
    final send = state.send;
    if (send == null ||
        send.phase == PendingSendPhase.sending ||
        send.phase == PendingSendPhase.included) {
      return;
    }
    state = state.copyWith(checking: true, overdue: _isOverdue(send));
    PendingSend next = send;
    var failed = false;
    try {
      if (!await _belongsToThisWallet(send)) {
        if (ref.mounted && identical(state.send, send)) await _publish(null);
        return;
      }
      final repository = ref.read(walletRepositoryProvider);
      final nonce = await repository.getAccountNonce(send.from);
      final chainNonce = nonce.fold<BigInt?>((_) {
        failed = true;
        return null;
      }, BigInt.tryParse);
      if (chainNonce != null && chainNonce > BigInt.parse(send.nonce)) {
        next = send.copyWith(phase: PendingSendPhase.nonceUsedUnmatched);
        final hash = send.hash;
        if (hash != null) {
          final found = await repository.findIncludedBlock(send.from, hash);
          // A failed history read leaves it unmatched, and it is checked again.
          final height = found.getOrElse((_) => null);
          if (height != null) {
            next = send.copyWith(
              phase: PendingSendPhase.included,
              blockHeight: height,
            );
          }
        }
      }
    } catch (_) {
      failed = true;
    }
    if (!ref.mounted) return;
    // A new send or a dismissal arrived during the reads; this answer is old.
    if (!identical(state.send, send)) {
      state = state.copyWith(checking: false);
      return;
    }
    final changed = next.phase != send.phase;
    if (changed) {
      await ref
          .read(walletSecureStorageProvider)
          .savePendingSend(next.encode())
          .catchError((_) {});
      if (!ref.mounted || !identical(state.send, send)) return;
    }
    state = PendingSendState(
      send: next,
      overdue: _isOverdue(next),
      checkFailed: failed,
    );
    _schedule();
    if (changed) {
      ref.invalidate(walletProvider);
      ref.invalidate(transactionsProvider);
    }
  }

  Future<void> _publish(PendingSend? send) async {
    state = PendingSendState(
      send: send,
      overdue: send != null && _isOverdue(send),
    );
    _schedule();
    try {
      await ref
          .read(walletSecureStorageProvider)
          .savePendingSend(send?.encode());
    } catch (_) {
      // It still works until the app restarts, and the 409 remains the backstop.
    }
  }

  bool get _needsPolling {
    final send = state.send;
    if (send == null || state.overdue) return false;
    return switch (send.phase) {
      PendingSendPhase.submitted || PendingSendPhase.outcomeUnknown => true,
      // Waits only for history to catch up, and only within the time limit.
      PendingSendPhase.nonceUsedUnmatched =>
        send.hash != null &&
            ref.read(pendingSendClockProvider)().difference(send.submittedAt) <
                pendingSendTimeLimit,
      PendingSendPhase.sending || PendingSendPhase.included => false,
    };
  }

  /// One read every interval while it's waiting, none once it's settled or the
  /// time limit passes; those are read on Check now and on returning to the app.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_needsPolling) return;
    _timer = Timer.periodic(pendingSendPollInterval, (_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.detached) {
        return;
      }
      unawaited(check());
    });
  }
}
