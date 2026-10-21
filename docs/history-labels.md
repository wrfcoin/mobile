# Wallet history labels and bounded earnings discovery

Implementation plan: label known network operations without inventing monetary
direction or amounts; retain explicit transfer and paid-reward semantics. Use
the shared wallet-history tile on Earnings and Wallet. On initial load/refresh,
continue empty credit pages sequentially until credits arrive or 30 total pages
have been examined, with progress, cancellation and incomplete-history feedback.

Validation: widget coverage for operation/transfer/reward labels, provider
coverage for bounded discovery, cancellation and concurrent-load refusal,
Flutter analysis and full tests, then profile APK build. Deployment and device
installation are separate owner actions.

## Source and rendering contract

Canonical operation names come from
[core4 TransactionType](https://github.com/wrfcoin/core4/blob/main/shared-protocol/src/blockchain/transaction.rs).
The tile labels all non-Transfer variants: Regular, Coinbase, Stake, Unstake,
NftCreation, NftTransfer, NftExecution, DataAnalysis, DataCollection, DataStorage,
EnvironmentalOffset, BridgeLock, BridgeUnlock, ContributionCommit,
ContributionReveal, ForecastCommit, ForecastReveal, OracleAttestation,
GovernanceProposal, GovernanceVote, GovernanceExecute, GovernanceFinalize,
GovernanceDelegate, TreasuryDeposit, TreasuryWithdraw, Reward,
ConfidentialTransfer, ShieldedDeposit, ShieldedWithdrawal, Layer2BatchSubmit,
RewardClaim, SlashingReport, OracleRegistration, StationRegistration,
FeatureScheduleExtension and SlashEvidenceReport. Unknown operation names use
“Network operation”. Exact operation type is preserved from tx_type when kind
and type are absent. Missing v2 type stays unknown instead of becoming Transfer.

Operation titles do not establish monetary movement: no direction arrow, sign
or amount line is shown. Included operations say “Included on chain”. This also
avoids falsely saying stake, treasury or privacy operations moved zero WRF.
Transfer directions still require reported direction/settlement, and only paid
weather/forecast ledger credits are rendered as received rewards.

Earnings is WalletScreen (app-bar title “Earnings”); its Recent Transactions and
Paid rewards both use TransactionTile and transactionsProvider. There is no
separate Earnings history widget. Chain's My account card also uses that tile.

## Discovery behavior

Initial load and refresh publish the first transaction page, then sequentially
follow empty credit pages until the first valid paid credits, cursor exhaustion,
any previously seen cursor in this discovery run or 30 pages total (including the initial page). While discovering,
Earnings shows “Checking earnings history…”. The transaction offset remains
unchanged; credit scans do not consume transaction pages. Reaching the bound
preserves the cursor for explicit Load more and forces the existing incomplete
history notice even if the server did not report incomplete history.

Requests are serialized across discovery, refresh and Load more. Refresh cancels
old transport and ignores stale results; concurrent refreshes coalesce. The provider auto-disposes when history loses its last listener;
disposal cancels Dio transport and prevents further requests/state publication.
Load more is disabled while scanning and locks before asynchronous address lookup.
No backend or consensus behavior changes. A rate-limited or unavailable backend
still follows existing error/unavailable behavior; the bounded scan is not proof
that a wallet has no lifetime earnings.
