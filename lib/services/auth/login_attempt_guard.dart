import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

/// Why a wallet login may or may not start now.
enum LoginPermitStatus {
  /// Go ahead. The attempt has already been recorded.
  allowed,

  /// A recent transport/server failure: wait for the backoff to expire.
  backoff,

  /// A definitive rejection, a wallet-connect handoff or the automatic
  /// ceiling: only an explicit user action may log in again.
  userActionRequired,

  /// The server answered 429. Nothing may log in until the lockout ends.
  rateLimited,

  /// The absolute per-window cap (automatic + manual) is reached.
  windowCapReached,

  /// The persisted guard state is corrupt. Automatic logins fail closed; an
  /// explicit sign-in may rebuild it (see [LoginAttemptGuard]).
  unavailable,

  /// Secure storage itself failed: the guard could not be read, written or
  /// read back. Fail closed; the user needs an actionable message.
  storageError,
}

/// How a started login ended.
enum LoginOutcome {
  success,

  /// Connection error, timeout, 5xx: retry later with backoff.
  transientFailure,

  /// The server or the client's own challenge check refused the login
  /// (4xx, malformed challenge, unexpected message): needs the user.
  rejected,

  /// 429: the backend's login limiter fired.
  rateLimited,
}

class LoginPermit {
  const LoginPermit(this.status, {this.until});

  final LoginPermitStatus status;

  /// When the current block ends, if it is time-bound.
  final DateTime? until;

  bool get allowed => status == LoginPermitStatus.allowed;
}

/// Persisted guard state. Kept in the wallet's secure key storage so the
/// foreground app and the Workmanager isolates (sensor_worker, sync_worker)
/// see the same ledger: flutter_secure_storage has no per-isolate cache.
class LoginGuardState {
  LoginGuardState({
    List<DateTime>? attempts,
    this.consecutiveFailures = 0,
    this.blockedUntil,
    this.rateLimitedUntil,
    this.userActionRequired = false,
    this.ceilingHold = false,
  }) : attempts = attempts ?? <DateTime>[];

  final List<DateTime> attempts;
  int consecutiveFailures;
  DateTime? blockedUntil;
  DateTime? rateLimitedUntil;
  bool userActionRequired;

  /// Set when the automatic ceiling is reached. Unlike
  /// [userActionRequired], a successful login does not clear it; only an
  /// explicit sign-in or a newly stored wallet does.
  bool ceilingHold;

  bool get heldForUser => userActionRequired || ceilingHold;

  /// Whether any value lies beyond what a real write could have produced
  /// (now + [LoginAttemptGuard.maxPlausibleLock]): e.g. a year-2100 lock
  /// from corruption that still parses. Such a ledger is treated as
  /// corrupt, not honoured.
  bool implausibleAt(DateTime now) {
    final horizon = now.add(LoginAttemptGuard.maxPlausibleLock);
    bool beyond(DateTime? t) => t != null && t.isAfter(horizon);
    return beyond(rateLimitedUntil) ||
        beyond(blockedUntil) ||
        attempts.any(beyond);
  }

  static LoginGuardState decode(String? raw) {
    if (raw == null || raw.isEmpty) return LoginGuardState();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    DateTime? at(Object? v) => v == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(v as int, isUtc: true);
    return LoginGuardState(
      attempts: [
        for (final v in (json['attempts'] as List<dynamic>? ?? const []))
          at(v)!,
      ],
      consecutiveFailures: json['consecutiveFailures'] as int? ?? 0,
      blockedUntil: at(json['blockedUntil']),
      rateLimitedUntil: at(json['rateLimitedUntil']),
      userActionRequired: json['userActionRequired'] as bool? ?? false,
      ceilingHold: json['ceilingHold'] as bool? ?? false,
    );
  }

  /// Best-effort recovery of a corrupt state: keeps every field that is
  /// still readable and restrictive (attempt timestamps, a 429 lock).
  /// Holds and backoff are dropped because only an explicit user action
  /// ever calls this, and an explicit action releases them anyway.
  static LoginGuardState salvage(String? raw, {DateTime? now}) {
    final state = LoginGuardState();
    // With [now], values no real write could have produced (beyond
    // now + [LoginAttemptGuard.maxPlausibleLock]) are dropped as corrupt.
    final horizon = now?.add(LoginAttemptGuard.maxPlausibleLock);
    DateTime? plausible(DateTime? t) =>
        t == null || horizon == null || !t.isAfter(horizon) ? t : null;
    Object? json;
    try {
      json = raw == null ? null : jsonDecode(raw);
    } catch (_) {
      json = null;
    }
    if (json is! Map) return state;
    // Each field is read on its own, so one bad field never hides another.
    try {
      final attempts = json['attempts'];
      if (attempts is List) {
        for (final v in attempts) {
          final t = plausible(lenientTimestamp(v));
          if (t != null) state.attempts.add(t);
        }
      }
    } catch (_) {}
    try {
      state.rateLimitedUntil = plausible(
        lenientTimestamp(json['rateLimitedUntil']),
      );
    } catch (_) {}
    return state;
  }

  /// A UTC instant from an int, a finite number or a numeric string holding
  /// epoch milliseconds, or null when it is anything else or outside
  /// DateTime's range. It never throws, so one bad field cannot hide the
  /// readable ones.
  static DateTime? lenientTimestamp(Object? v) {
    try {
      num? n;
      if (v is num) {
        n = v;
      } else if (v is String) {
        final text = v.trim();
        n = int.tryParse(text) ?? double.tryParse(text);
      }
      // NaN, ±Infinity and overflowing literals such as "1e999" are not
      // timestamps; round() on them would throw.
      if (n == null || !n.isFinite) return null;
      final ms = n is int ? n : n.round();
      const limit = 8640000000000000;
      if (ms < -limit || ms > limit) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'attempts': [for (final a in attempts) a.toUtc().millisecondsSinceEpoch],
    'consecutiveFailures': consecutiveFailures,
    'blockedUntil': blockedUntil?.toUtc().millisecondsSinceEpoch,
    'rateLimitedUntil': rateLimitedUntil?.toUtc().millisecondsSinceEpoch,
    'userActionRequired': userActionRequired,
    'ceilingHold': ceilingHold,
  });
}

/// Bounds wallet logins so the app can never burn the backend's login budget
/// (5 logins / 15 min / IP, then a 1 h ban; mobile#313).
///
/// - At most [maxAutomaticAttemptsPerWindow] logins per [window] may start
///   without the user. Reaching it sets [LoginGuardState.userActionRequired],
///   which only an explicit sign-in (or storing a new wallet) clears. The
///   window passing does not clear it.
/// - A transport/server failure backs off exponentially from [baseBackoff]
///   to [maxBackoff], with jitter in [50%, 100%] of the step.
/// - A definitive rejection requires the user.
/// - A 429 locks every login, manual included, for Retry-After (at least
///   [rateLimitLockout]).
/// - Even explicit sign-ins are capped at [maxAttemptsPerWindow] per window,
///   below the backend's 5.
///
/// Attempts are recorded when the permit is granted, before any request,
/// so a crash mid-login still counts. State that cannot be read or written
/// fails closed.
class LoginAttemptGuard {
  LoginAttemptGuard({
    required this._read,
    required this._write,
    DateTime Function()? clock,
    double Function()? random,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? math.Random().nextDouble;

  static const storageKey = 'wrf_auth_login_guard_v1';
  static const window = Duration(minutes: 15);
  static const maxAutomaticAttemptsPerWindow = 2;
  static const maxAttemptsPerWindow = 4;
  static const baseBackoff = Duration(minutes: 2);
  static const maxBackoff = Duration(minutes: 60);
  static const rateLimitLockout = Duration(minutes: 60);

  /// The longest restriction any write can produce. A server Retry-After
  /// longer than this is recorded as this maximum, and a stored value
  /// beyond now + this is implausible, so it is treated as corrupt (routed
  /// to the explicit "Sign in again" recovery) rather than honoured.
  static const maxPlausibleLock = Duration(days: 7);

  final Future<String?> Function() _read;
  final Future<void> Function(String value) _write;
  final DateTime Function() _clock;
  final double Function() _random;

  /// Jittered exponential backoff after [failures] consecutive failures.
  static Duration backoffFor(
    int failures, {
    required double Function() random,
  }) {
    final n = math.max(1, failures);
    final exp = math.min(n - 1, 20);
    final stepMs = math.min(
      baseBackoff.inMilliseconds * (1 << exp),
      maxBackoff.inMilliseconds,
    );
    final r = random().clamp(0.0, 1.0);
    final jittered = (stepMs * (0.5 + 0.5 * r)).round();
    // Never shorter than the base step, so jitter cannot undercut it.
    return Duration(
      milliseconds: math.max(jittered, baseBackoff.inMilliseconds),
    );
  }

  Future<LoginGuardState?> _load() async {
    try {
      return LoginGuardState.decode(await _read());
    } catch (_) {
      return null;
    }
  }

  /// Every attempt granted in this isolate (automatic and manual), plus the
  /// latest 429 lock seen here: a second ledger that corrupting the stored
  /// one cannot reset. Permits merge it with the persisted ledger as a
  /// multiset union by millisecond (no double counting).
  static final List<DateTime> _isolateAttempts = <DateTime>[];
  static DateTime? _isolateRateLimitedUntil;

  /// Resets the in-isolate state between tests.
  static void resetIsolateStateForTest() {
    _isolateAttempts.clear();
    _isolateRateLimitedUntil = null;
    _tail = Future<void>.value();
  }

  /// max(Retry-After, [rateLimitLockout]): the server's lock is honoured
  /// in full, never shortened.
  static Duration _lockoutFor(Duration? retryAfter) {
    final lockout = retryAfter != null && retryAfter > rateLimitLockout
        ? retryAfter
        : rateLimitLockout;
    return lockout > maxPlausibleLock ? maxPlausibleLock : lockout;
  }

  static DateTime _ms(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    t.millisecondsSinceEpoch,
    isUtc: true,
  );

  /// Folds the in-isolate ledger into [state] (after pruning both).
  static void _mergeIsolateLedger(LoginGuardState state, DateTime now) {
    _isolateAttempts.removeWhere((a) => now.difference(a) >= window);
    int count(List<DateTime> xs, int ms) =>
        xs.where((x) => x.millisecondsSinceEpoch == ms).length;
    final persisted = [for (final a in state.attempts) _ms(a)];
    final merged = <DateTime>[...persisted];
    for (final ms in {
      for (final a in _isolateAttempts) a.millisecondsSinceEpoch,
    }) {
      final extra = count(_isolateAttempts, ms) - count(persisted, ms);
      for (var i = 0; i < extra; i++) {
        merged.add(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
      }
    }
    merged.sort();
    state.attempts
      ..clear()
      ..addAll(merged);
    final isolateLock = _isolateRateLimitedUntil;
    if (isolateLock != null &&
        (state.rateLimitedUntil == null ||
            isolateLock.isAfter(state.rateLimitedUntil!))) {
      state.rateLimitedUntil = isolateLock;
    }
  }

  Future<bool> _save(LoginGuardState state) async {
    try {
      await _write(state.encode());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Drops attempts older than one window. Nothing else is ever shortened:
  /// a write may only add restrictions or release what the user explicitly
  /// released. A future-stamped attempt therefore keeps counting until the
  /// clock passes it, and a stored lock is honoured in full.
  void _prune(LoginGuardState s, DateTime now) {
    s.attempts.removeWhere((a) => now.difference(a) >= window);
  }

  /// One in-isolate queue for every read-modify-write of the persisted
  /// state, shared by every guard instance in this isolate. The foreground
  /// app holds several ApiClients (the provider's, and each SyncWorker's),
  /// so without this, overlapping permits and outcomes lose updates. Only
  /// the foreground isolate writes this state: Workmanager isolates never
  /// start a login (ApiClient `canStartLogin: false`), so there is no
  /// cross-isolate writer to race with.
  static Future<void> _tail = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Asks to start one login now. When allowed, the attempt is recorded.
  Future<LoginPermit> requestPermit({required bool userInitiated}) =>
      _serialized(() => _requestPermit(userInitiated: userInitiated));

  Future<LoginPermit> _requestPermit({required bool userInitiated}) async {
    try {
      return await _requestPermitUnsafe(userInitiated: userInitiated);
    } catch (_) {
      // Never let an unexpected state crash a caller (e.g. the sign-in
      // button): refuse, with the actionable storage message.
      return const LoginPermit(LoginPermitStatus.storageError);
    }
  }

  Future<LoginPermit> _requestPermitUnsafe({
    required bool userInitiated,
  }) async {
    final String? raw;
    try {
      raw = await _read();
    } catch (_) {
      return const LoginPermit(LoginPermitStatus.storageError);
    }
    final now = _clock();
    LoginGuardState state;
    var corrupt = false;
    try {
      state = LoginGuardState.decode(raw);
      // Readable but impossible (beyond now + maxPlausibleLock): corrupt.
      corrupt = state.implausibleAt(now);
    } catch (_) {
      state = LoginGuardState();
      corrupt = true;
    }
    if (corrupt) {
      // Automatic logins fail closed; an explicit sign-in may rebuild the
      // ledger from whatever is still readable and plausible. It must store
      // the rebuilt ledger durably before any request (below).
      if (!userInitiated) {
        return const LoginPermit(LoginPermitStatus.unavailable);
      }
      state = LoginGuardState.salvage(raw, now: now);
    }
    _prune(state, now);
    _mergeIsolateLedger(state, now);

    final rateLimitedUntil = state.rateLimitedUntil;
    if (rateLimitedUntil != null && now.isBefore(rateLimitedUntil)) {
      return LoginPermit(
        LoginPermitStatus.rateLimited,
        until: rateLimitedUntil,
      );
    }
    if (state.attempts.length >= maxAttemptsPerWindow) {
      return LoginPermit(
        LoginPermitStatus.windowCapReached,
        until: state.attempts.first.add(window),
      );
    }

    if (userInitiated) {
      state
        ..userActionRequired = false
        ..ceilingHold = false
        ..blockedUntil = null
        ..consecutiveFailures = 0;
    } else {
      if (state.heldForUser) {
        return const LoginPermit(LoginPermitStatus.userActionRequired);
      }
      final blockedUntil = state.blockedUntil;
      if (blockedUntil != null && now.isBefore(blockedUntil)) {
        return LoginPermit(LoginPermitStatus.backoff, until: blockedUntil);
      }
      if (state.attempts.length >= maxAutomaticAttemptsPerWindow) {
        state.ceilingHold = true;
        await _save(state);
        return const LoginPermit(LoginPermitStatus.userActionRequired);
      }
    }

    final attemptAt = _ms(now);
    state.attempts.add(attemptAt);
    // Granting the attempt that reaches the automatic ceiling latches the
    // hold now, so it survives the outcome, window pruning and a restart.
    if (!userInitiated &&
        state.attempts.length >= maxAutomaticAttemptsPerWindow) {
      state.ceilingHold = true;
    }
    // Every granted permit must be durable before any request: written,
    // then read back byte-identical (a store that drops writes, fails, or
    // returns something else refuses the login). This applies to readable
    // and recovered ledgers alike.
    final encoded = state.encode();
    if (!await _save(state)) {
      return const LoginPermit(LoginPermitStatus.storageError);
    }
    try {
      if (await _read() != encoded) {
        return const LoginPermit(LoginPermitStatus.storageError);
      }
    } catch (_) {
      return const LoginPermit(LoginPermitStatus.storageError);
    }
    // Only a permit that is actually granted (a request will follow) is
    // counted in the in-isolate ledger.
    _isolateAttempts.add(attemptAt);
    return const LoginPermit(LoginPermitStatus.allowed);
  }

  /// Whether an automatic login is currently held for the user, without
  /// recording anything.
  Future<bool> requiresUserAction() async {
    final state = await _load();
    return state == null || state.heldForUser;
  }

  Future<void> recordOutcome(LoginOutcome outcome, {Duration? retryAfter}) =>
      _serialized(() => _recordOutcome(outcome, retryAfter: retryAfter));

  Future<void> _recordOutcome(
    LoginOutcome outcome, {
    Duration? retryAfter,
  }) async {
    if (outcome == LoginOutcome.rateLimited) {
      final lockout = _lockoutFor(retryAfter);
      final until = _clock().add(lockout);
      final current = _isolateRateLimitedUntil;
      if (current == null || until.isAfter(current)) {
        _isolateRateLimitedUntil = until;
      }
    }
    // A success releases nothing: a permit is only granted when no hold is
    // up, or after an explicit sign-in already released it. Clearing here
    // could erase a hold that another client set while this login was in
    // flight. Writes only ever add restrictions (or record an explicit
    // user release).
    if (outcome == LoginOutcome.success) return;
    final state = await _load();
    if (state == null) return; // unreadable or corrupt: never overwrite
    final now = _clock();
    _prune(state, now);
    void extendBackoff() {
      state.consecutiveFailures += 1;
      final until = now.add(
        backoffFor(state.consecutiveFailures, random: _random),
      );
      final current = state.blockedUntil;
      if (current == null || until.isAfter(current)) {
        state.blockedUntil = until;
      }
    }

    switch (outcome) {
      case LoginOutcome.success:
        return;
      case LoginOutcome.transientFailure:
        extendBackoff();
      case LoginOutcome.rejected:
        extendBackoff();
        state.userActionRequired = true;
      case LoginOutcome.rateLimited:
        final lockout = _lockoutFor(retryAfter);
        final until = now.add(lockout);
        final current = state.rateLimitedUntil;
        if (current == null || until.isAfter(current)) {
          state.rateLimitedUntil = until;
        }
        state.userActionRequired = true;
    }
    await _save(state);
  }

  /// Holds automatic logins until the user acts: the server rejected even a
  /// freshly issued session (a confirmed, unrecoverable auth rejection).
  Future<void> holdForUser() => _serialized(() async {
    final state = await _load();
    if (state == null) return;
    state.userActionRequired = true;
    await _save(state);
  });

  /// Storing a new wallet is an explicit user action: it releases the
  /// user-releasable holds (userActionRequired, ceilingHold, backoff). The
  /// attempt ledger and a 429 lock stay, because the backend's budget is
  /// per IP, not per wallet.
  ///
  /// Best effort, and it never writes on uncertainty. If the guard cannot
  /// be read (storage I/O) or decoded (corrupt), it returns without writing
  /// and the stored ledger is kept as it is. A corrupt guard is recovered
  /// only by an explicit "Sign in again", which keeps what is readable. A
  /// write failure is swallowed: the import must not fail because of it.
  static Future<void> releaseForNewWallet({
    required Future<String?> Function() read,
    required Future<void> Function(String value) write,
  }) => _serialized(() async {
    final LoginGuardState state;
    try {
      state = LoginGuardState.decode(await read());
    } catch (_) {
      return;
    }
    if (!state.heldForUser &&
        state.blockedUntil == null &&
        state.consecutiveFailures == 0) {
      return; // nothing to release: no write at all
    }
    state
      ..userActionRequired = false
      ..ceilingHold = false
      ..blockedUntil = null
      ..consecutiveFailures = 0;
    try {
      await write(state.encode());
    } catch (_) {
      // The hold then stays; "Sign in again" reports the storage problem.
    }
  });
}
