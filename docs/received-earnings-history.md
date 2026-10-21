# Received earnings history

Wallet history schema v2 (backend PR #1479, core4 PR #3520) supplies explicit transfer directions and a separate paginated paid-reward section. Weather and forecast records require a valid event ID, the requested beneficiary, settlement `paid`, direction `received`, and a positive u128 decimal-string amount. Generic Reward transactions, estimates, pending events, achievements, malformed amounts, and other beneficiaries do not create received-income rows.

Rows use exact integer conversion at 100,000,000 base units per WRF. Unknown direction and self transfers have no plus sign; unknown amounts remain unavailable. Event IDs are separate from transaction hashes. Screen keys fall back safely to a reported hash or section/type/index when an event ID is missing; the API boundary rejects paid credit records missing an event ID.

Transactions retain their bounded-window notice and offset pagination. Paid rewards have no reported settlement date, height, or transaction hash and are displayed separately with that limitation visible. Their cursor is independent of transaction offsets, can advance through empty pages, and deduplicates stable event IDs. Refresh restarts both streams. No optimistic income is added on submission.

Achievement payouts remain excluded until a confirmed-paid ledger event with verified provenance exists. This source change does not deploy the API or establish installed-device behavior. Merge after the upstream schema PRs; no changes to Send-screen files or shared WRF unit helpers.
