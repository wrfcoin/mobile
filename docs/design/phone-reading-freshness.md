# Phone reading freshness and offline earning

Refs #323. SOL-K PM readiness assignment, 2026-10-02.

## Current boundary

Inspected mobile main `488b51cf4edf8a8b8f538b72eebee846ec003e04` and
core4 main `df6264ef4a79bdc40b705405bc15e404915d3ea0` locally. No live
node or attester was contacted. mobile#339 and backend#1312 are merged;
subsequent mobile collection work retains the 50-minute upload cutoff.

`MechanicalPolicy` defaults `max_age_secs` to 3600 and refuses an observation
older than that at evaluation time. Freshness also decreases confidence.
The attester may override its maximum age through configuration; this is a
service policy, not a hard-coded consensus rejection at HTTP submission.
An admitted commit/reveal therefore does not establish a reward. The mobile
cutoff leaves ten minutes for transport, mempool and attester delay, without
guaranteeing approval. Historical references and station ordering are further
constraints on delayed earning; a larger number alone is insufficient.

The current worker prunes once, after connectivity/wallet/backoff guards. It
does not prune on an offline or locked run. A reading can age out during
registration, a prepare response, signing, another reading's upload, or retry
delay. The dashboard does not tell a new collector about the earning deadline.

## Mobile delivery, without changing the earning policy

1. Keep the existing 50-minute cutoff and oldest-first order. Prune using the
   existing atomic deletion plus durable notice before connectivity/wallet/
   backoff guards and before each batch. No schema or storage primitive change.
2. The worker supplies a clock-based eligibility predicate to its sole
   production `submitBatch` call. The repository checks it before prepare,
   after prepare before signing, and after signing before submit. An aged-out
   reading is skipped, with no fabricated acceptance or reward. Earlier
   accepted readings still complete. Expiry is separate from retry failure.
3. After a batch, prune newly expired unsynced rows with the same durable
   counter and include them in the run notice. Only rows still unsynced are
   removed; an already admitted reading is retained as synced.
4. Explain in Collect, before a stale notice is needed: uploads stop after
   50 minutes; attester approval is normally needed within about one hour;
   offline saved data and upload acceptance do not guarantee rewards.
5. Pin clocks in controls: offline/backoff pruning, retry/registration delays,
   slow prepare/sign/submit, mixed fresh/expired batches, exact cutoff, durable
   notice, zero transport for expired data, mounted disclosure. Mutate a
   boundary recheck and demand failure. Run analysis and full two-worker tests.

The eligibility hook keeps lower-level signing/vector tests independent of
wall-clock time; every production weather-upload path goes through SyncWorker.
No coordinate precision, wallet/session/backoff policy, activation rule or
scheduled consensus behavior changes. Device clocks remain untrusted; the
attester continues to decide freshness. A network request already in flight
cannot be recalled, and even an on-time submission can miss the earning window.

## Owner decision for r19

The owner selected A in the PM assignment session: retain current freshness
for r19, publish the mobile honesty and boundary checks, and describe longer
offline earning as unavailable. This patch implements that decision.

Deferred option B: commission a separate historical-observation protocol design for a
later unscheduled node feature. Before implementation, define a maximum delay,
trusted capture/commit time, reference availability at capture time, station
ordering/replay rules, confidence/reward decay, and deterministic old/new
activation vectors. Coordinate core4, backend and reference-data owners. Never
rewrite a captured timestamp to upload time: that changes the authenticated
observation and can pretend old weather is current.

No node/config change or activation is proposed by this mobile patch. The
one-hour earning constraint remains by the approved r19 policy; this work
completes the selected mobile expiry handling and disclosure.

Deploy notes: app-tier r19 per PM assignment. No new dependency, environment,
migration, APK, deploy operation or live-testnet request.
