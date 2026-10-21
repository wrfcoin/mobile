# Profile endpoint verification

Verified against backend origin/main `70ea2808c1dbe07bba2f5e543af6e1ce8966ad30` and infra origin/main `bb3db722b2ba28b1ef0d98b191f8650a0d286fbd`. This is source verification, not a phone or deployment smoke test. Mobile builds on merged #410.

## Leaderboard contract

- Backend `server/routes/weather-leaderboard-routes.ts:244-254` accepts metric, period and limit; defaults are earnings/7d/25 and the backend cap is **100**, with no query-order restriction. The stricter public edge requires **metric, period, limit in that order**, limit **1..30**: infra `testnet/edge/public_onboarding.caddy:328-337`. Mobile requests `metric=earnings&period=7d&limit=30` through both direct and edge paths.
- Exact amounts are the `earningsBaseUnits` string and `earningsWrf` display string, never numeric `value`: backend `server/routes/weather-leaderboard-routes.ts:596-609,632-633`. The envelope declares lifetime earnings and unit availability at `:638-650`. `shared/amount-unit-contract.ts:24-34` declares WRF, eight decimals, string scale and base/display field labels. Mobile validates these before using its existing BigInt formatter.
- Unprovable earnings return 503, `success:false`, `amountUnits.available:false`, `unavailable:['earnings']`, and no rows: `server/routes/weather-leaderboard-routes.ts:350-359,544-555`. An unavailable marker on a 200 also fails closed. Genuine empty boards require a successful, available unit envelope.
- Backend tests: `__tests__/routes/weather-leaderboard-chain-rows-1456.test.ts:101-122` proves the 1524000000/15.24 paid row; `:125-154` covers period semantics, BigInt ordering and ranked-row limits; `:156-169` covers unavailable/no partial rows. `__tests__/routes/weather-leaderboard-earnings.test.ts:59-83,92-105` covers base/display units and unavailable amounts.
- `test/fixtures/leaderboard_backend_1456.json` is a minimal contract fixture: paid amount and display value copied from the backend #1456 test above, envelope/unit fields copied from the route and shared contract. The display name/address are synthetic, not a captured live response. Existing widget fixtures additionally exercise served address visibility and own-row marking. No base-unit value passes through floating-point parsing.

## Endpoint table (step 1.2)

Paths include the ApiClient `/api` prefix. Mounts are in backend `server/enhanced_unified_api_optimized.ts:1531,1565,1606,1609,1626`.

| Profile surface | Endpoint | Backend origin/main | UI behavior |
| --- | --- | --- | --- |
| Leaderboard tab and standalone route | GET `/api/weather/leaderboard?metric=earnings&period=7d&limit=30` | Present, route `server/routes/weather-leaderboard-routes.ts:244` | Shared renderer for ranked rows, empty board, unavailable and Retry |
| Achievements | GET `/api/achievement/:userId` | Route present at `server/routes/achievementRoutes.ts:51`, but unwired guard at `:25` returns 501 (`server/middleware/require-wired-storage.js:56-70`) | Honest static unavailable message; no fetch or placeholder badges |
| Achievement claim | POST `/api/v1/rewards/claim/:achievementId` | Present, `server/routes/rewards.ts:481` | Hidden while achievements are unavailable; no claim request |
| Claim history repository method | GET `/api/v1/rewards/history?userId=...` | Present, `server/routes/rewards.ts:772` | Not called by Profile |
| Data desert map | GET `/api/weather/coverage-zones` | Present, `server/routes/weather-routes.js:546-601`; DB-derived bounded zones, empty zones on DB failure | Retained; no invented zone rows |
| NFT portfolio | GET `/api/nft/portfolio/:userId` | Absent; NFT router has GET `/` and `/:id` (`server/routes/nft-routes.js:63,112`), no portfolio handler | Hidden, no request, including when an old NFT flag is saved |
| NFT claim | POST `/api/nft/claim` | Absent; POST route inventory at `server/routes/nft-routes.js:144,178,239,270` has no claim handler | Hidden, no request |
| Settings and privacy | No backend request | Local preferences/location/consent controls in `app_settings_screen.dart` and `privacy_center_screen.dart` | Retained |
| Map tiles | GET `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | External tile service, not a backend route | Existing map background retained |

Profile is default-on for fresh preferences. Saved explicit opt-outs remain respected. NFT and connectivity-hardening defaults remain unchanged.

## Local validation

- RED before implementation: new contract target had 1 pass / 12 failures against #410's code (missing query and unchecked units).
- Independent query-order mutation after implementation: swapping metric and period failed the query test (0 pass / 1 failure); restored before final checks.
- Focused gamification and actual-router navigation: 114 passed.
- `flutter analyze --no-pub`: no issues.
- Full `flutter test --no-pub --concurrency=2`: 1843 passed, 3 skipped, no failures. Two local-stack E2E tests require `WRFCOIN_E2E_BASE_URL`; one opt-in live-send check requires `WRFCOIN_LIVE_SEND_CHECK=1`. No deployment or phone claim is made.
- `git diff --check`: clean. Flutter did not modify `android/gradle.properties`.
