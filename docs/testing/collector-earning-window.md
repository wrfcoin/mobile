# Collector earning-window evidence

Refs mobile#402, infra#1256, mobile#384. Local synthetic test evidence only; no device, attester deployment or payment receipt. Production eligibility and notice UI are unchanged.

The attester mechanical policy uses age >3600s for refusal (`shared-protocol/src/oracle/mechanical.rs`, DEFAULT_MAX_AGE_SECS and the age check). Its exact3600s boundary is inclusive; the existing native test `confidence_decays_with_age_but_stays_above_the_floor` explicitly asserts approval at the window edge (source-only, not executed here). Source pin: 1b908b384b2be9eca9c9282895bf85dbd37a0640. The phone deliberately uses a stricter3000s (50-minute) inclusive upload cutoff, leaving about ten minutes for mining/attestation. At3600s a saved phone reading has already expired locally; this test does not extend its eligibility or prove attester execution.

| Existing path / added test | Boundary evidence |
| --- | --- |
| `test/features/collector/presentation/resume_expiry_notice_test.dart` — real app resume at one hour persists expiry notice; dismiss acknowledges only displayed drops | Actual WrfcoinApp observer and CollectorNotifier, real SyncWorker/repository, native file-backed SQLite. At3600s stale rows disappear, fresh row stays. Real app/connection restart retains notice count. Actual dismiss subtracts only the displayed count and preserves a later background drop. Offline reaches no signer/API and shows unable-to-earn copy, no settled WRF. |
| `test/features/collector/data/submit_freshness_test.dart` — six expiry-stage cases | Before prepare, after prepare and after signing at3000s and3600s crossings. No expired submit/sync/reward; after-prepare expiry performs no commit signature. |
| `test/services/background/sync_worker_freshness_test.dart` — exact cutoff survives; older by one second is removed | Actual mobile3000s boundary; offline/backoff/registration/prepare/retry delays preserve durable discard counts. |

Independent after-prepare and after-signing recheck removal each produces two failures. Omitting actual app resume and erasing all counts during acknowledgement each fails the mounted test. Production files are restored after every mutation; no mutation ships.

The readiness row “a phone reading earns only if it reaches the attester within ~1 hour” stays PARTIAL for runtime/payment evidence. These source/test links improve local boundary coverage; upload acceptance does not guarantee reward. Invitee instructions should tell users to reconnect promptly, acknowledge ineligible-reading notices and collect again, rather than promise offline payment.
