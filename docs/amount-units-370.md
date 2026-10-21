# PWS and treasury amount units

Refs #370. Source snapshot: backend main
`2948f013725ffbb019d5bd0d91093876bcc3937b`.

## Treasury

`server/routes/governance-routes.ts:563-585` reads executed
`treasury_transaction` amounts from `treasury_consolidated`, subtracts
withdrawals from deposits, and returns `data.balance` formatted to eight
decimal places. It does not select a denomination, group by token, report a
scale, or obtain this balance from core4.

`shared/schema-governance-consolidated.ts:64-73` requires a generic
`tokenAddress` and defines `amount` as decimal(36,18). Deposit and withdrawal
handlers (`governance-routes.ts:865-925`) accept token addresses and amounts.
Neither database precision nor eight-place response formatting establishes
WRF display units or WRF base units. The endpoint also combines token amounts;
the mobile display does not establish that total's economic interpretation.

The client reads the actual `data` envelope, preserves the reported decimal
string, and displays **Unit not reported**. It retains legacy flat and
`treasury` envelopes and explicitly supplied currency metadata, without
inventing a currency. A legacy numeric balance suffix can be removed only when
it matches that response's explicit currency; the display still makes no unit
claim. Backend floating-point aggregation precision is outside this mobile
change; preservation starts at the response string.

## PWS earnings

`lib/core/constants/api_constants.dart` requests `/oracle/stations`.
The backend entrypoint mounts the submit router at
`enhanced_unified_api_optimized.ts:1497` and the oracle/detail routers at
`:1565-1566`. Those routers have no station-list response reporting earnings.
There is no established response contract tying this field to core4 balance
units or a WRF denomination. This audit does not establish a live endpoint.

If an earnings number is reported, the screen preserves it without conversion
and displays **Unit not reported**. Missing or malformed amounts are shown as
unavailable, whereas a reported zero remains zero. No API or chain schema is
added. Establishing a denomination and scale in a future backend contract is
required before either display can apply WRF conversion or label it WRF.

## Verification

`test/features/amount_units_370_test.dart` exercises the real PWS API read and
governance repository-to-screen path, plus the treasury card. It covers decimal
strings larger than JavaScript's safe integer range, zero, absent/malformed
amounts, API errors, and absence of guessed unit labels. Tests use local Dio
responses and do not contact a live backend.
