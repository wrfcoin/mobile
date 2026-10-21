# Role earnings capabilities recovery

Base: mobile main `d02ee63b5bb42502de1781993553bed5bf119c91` (PR 431). Scope: the earnings capability provider and its board/Profile consumers only.

A transport or malformed-envelope failure in `/capabilities` now becomes a sanitized UNKNOWN error, rather than a cached OFF value. An explicit non-enabled status still returns OFF; the role controls and own summary remain hidden and the legacy weather leaderboard remains available. No other capability provider or API contract changed.

`earningsReadProvider` disposes when unused and disables Riverpod's automatic retry. UNKNOWN has an unavailable message, Retry and an always-scrollable pull-to-refresh surface. Those actions invalidate and re-read capabilities, with an in-flight guard that coalesces overlapping Retry actions. Loading replaces the error surface. A successful recovery mounts the role board and requests exactly one ranking; another failure stays UNKNOWN without background requests. Entry into a board retries a cached UNKNOWN once, including when a Profile summary holds the shared provider alive. No tight loop or periodic refresh exists.

The Profile own-summary continues withholding amounts on OFF, UNKNOWN and loading. On recovery it follows the shared enabled provider, then the existing server-confirmed ownership check; no profile read is made while capability status is UNKNOWN/OFF. Existing role/period, amount, privacy and identity-refresh contracts remain unchanged.

Regression tests use scripted Dio responses through the real repository/provider and mounted screens. Request counts assert one initial read, no extra reads over 30 seconds, one user-triggered recovery read, one board request after success, and no board/profile requests for OFF or UNKNOWN. Coverage includes Retry, pull-to-refresh, cached-UNKNOWN next entry, repeated failure, overlapping taps, malformed envelopes, and the shared Profile consumer. The previous missing-status-as-OFF case is now covered as malformed UNKNOWN with Retry.

Validation:
- `dart analyze`: no issues, exit 0.
- Focused `flutter test --no-pub --concurrency=2 test/features/gamification --reporter expanded`: 166 passed, no failures, exit 0.
- Full `flutter test --no-pub --concurrency=2 --reporter expanded`: 1,947 passed, 3 opt-in skips, no failures, exit 0. No implementation or test files changed after the full run began.

Local source/contract evidence only; no APK/device, live-host, deployment or merge evidence.
