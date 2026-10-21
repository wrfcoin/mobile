# Mobile role earnings contract

Backend contract: main `920b2f81d8c6cbab0c2fca6a01c91b6da63e60ae` (B2, backend PR 1481).

GET `/earnings/leaderboard` uses exactly `role=<role>&period=<all|7d|30d>&limit=30` in Dio insertion order. The existing API client prefixes `/api`. No duplicate, extra or reordered parameters are emitted. Profile reads use existing `/operators/<own login address>/profile`; the own summary additionally requires server `isYou: true`, without deriving ownership from labels or an echoed address. Legacy DB totals are never substituted for role amounts.

The new controls and summary appear only when `/capabilities` reports `earningsRead` as operational, degraded or configured. Absent, malformed, unavailable, simulated or failed capability reads fail closed. Capability-OFF retains the legacy weather board. Producer and attester support all-time, 7-day and 30-day payment scopes. Contribution/forecast paid-event coverage is unavailable in B2; nodes are unsupported with the exact unimplemented-payments copy. Only a complete available response with an empty list is an observed-empty board.

Models validate WRF/8 decimals/100000000 scale, role and scope agreement, contiguous coverage from height 1, as-of height/hash/time, canonical rollback policy, exact payment-window duration, rank sequence, unique opaque profile keys, shortened addresses and exact display/base-unit agreement. BigInt renders amounts without double conversion. Display names come exclusively from the backend's approved mapping or neutral aliases. Own-summary providers observe wallet/session invalidation, dispose when unused and withhold old amounts during identity refresh. Role/period switches clear old rows immediately; request generations and mounted checks suppress old responses and failures. Retry preserves the selected role/period. Partial/unproven boards show no rows.

`contract-fixtures/role-earnings-b2.json` is a synthetic cross-layer wire fixture based on the final backend earnings source, route projection and B2 PostgreSQL assertions. It contains no operational identities, host mapping or credentials. Repository, model, provider and mounted embedded/standalone tests consume the same fixture.

Validation:
- Initial focused gamification suite: 156 passed.
- Query-order mutation: moved period before role in the real repository; exact producer/all URI test failed (exit 1). Restored correct order before final validation.
- Final `dart analyze`: no issues.
- First full Flutter suite: 1,938 passed, 3 opt-in skips, no failures.
- Final `flutter test --no-pub --concurrency=2 --reporter expanded` including wallet-change regression: 1,939 passed, 3 opt-in skips, zero failures, exit 0. No production files changed after this run began.

Evidence is local source/contract validation. No deployment, APK, live node API, device acceptance or GO evidence is claimed.
