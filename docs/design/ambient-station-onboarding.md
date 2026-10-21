# SOL-K: Ambient station onboarding from the phone

Refs mobile#72, mobile#272, backend#1261, backend#822.
Round 3 assignment, 2026-10-02. Design written before production changes.

## Scope and existing evidence

The Round 3 instruction authorizes the Ambient phone path behind a flag. It
supersedes #272's older decision that physical station pairing stayed on the
web. It does not authorize BLE, Ecowitt/Davis pairing, firmware configuration,
new ingestion, provider-key logging, arbitrary-host fetching or deployment.

Mobile main `488b51cf4edf8a8b8f538b72eebee846ec003e04` has a default-off
`enablePwsAutoDiscovery` flag and a PWS banner backed by no-op scan/probe
functions. The banner is unreachable when there are no linked stations.
It must not present an empty no-op result as a real LAN scan.

Backend main `65efa14d7b6e4561c6ce4e08b0f6b66f2b11d1a7` has authenticated
`POST /api/weather/stations/verify-key` and `POST /api/weather/stations`.
backend#1267, #1273 and #1357 implement #1261 MAC membership, canonicalization,
active-station uniqueness and same-station idempotence. The issue's OPEN status
does not mean those protections are absent. No live endpoints were contacted.

## What the vendors expose on the LAN

| Vendor | Documented interface | What it proves |
| --- | --- | --- |
| Ambient Wi-Fi consoles | Manufacturer support lists TCP 45000 and UDP 46000/43210, a framed configuration protocol with broadcast 0x12 and station-MAC read 0x26. Model/firmware support varies. | Device reachability and advertised identity only; no wallet or account ownership. |
| Ecowitt GW1000/GW1100 family | Vendor TCP protocol specifies UDP broadcast 0x12 replies with MAC/IP/port, app port 46000 and TCP server 45000. Newer HTTP documentation includes get_livedata_info and get_network_info on the gateway. | Local identification/data only; a private IP or unauthenticated reply is not ownership proof. |

Ambient's supported account REST interface enumerates devices, including MACs,
using an API key and application key. This delivery uses that interface through
the existing backend verifier, rather than claiming untested cross-model LAN
or BLE support. Account discovery is explicitly labeled in the phone UI.
The old #72 assumption that hub.ambientweather.net is a generic local HTTP
endpoint is not supported by the manufacturer sources inspected here.

Primary sources (read 2026-10-02):

- [Ambient official REST specification](https://github.com/ambient-weather/api-docs/blob/master/apiary.apib)
- [Ambient WS-2902 support: ports and configuration protocol](https://ambientweather.com/support/ws-2902-weather-station-support)
- [Ecowitt vendor TCP protocol](https://osswww.ecowitt.net/uploads/20211104/WN1900%20GW1000%2C1100%20WH2680%2C2650%20telenet%20v1.6.3%20.pdf)
- [Ecowitt vendor HTTP protocol](https://oss.ecowitt.net/uploads/20260109/HTTP%20API%20interface%20Protocol%20%28Generic%29-%28V1.0.5-2025-10-08%29%20.pdf)

## Ownership and request boundaries

1. The user opens the default-off Ambient entry from Weather Stations, including
   its empty/error states. No provider request occurs on build or without an
   explicit button press. Existing wallet authentication gates both operations.
2. POST only `{provider: 'ambient', apiKey, appKey}` to the configured backend's
   fixed verify-key route. Accept only `valid: true` and a well-formed list of
   account devices with canonical six-byte MACs. No user-entered MAC or host.
3. Select one device; collect a name and a manually entered station location.
   Quantize validated latitude/longitude to 0.1 degrees before submission.
   Vendor-returned fine coordinates are not retained or auto-filled.
4. POST the selected verified MAC, provider 'ambient', coarse location, name,
   `ambientApiKey` and `ambientAppKey` to the fixed station-registration route.
   Never supply ownerAddress/admin credentials. The authenticated backend
   derives the owner, revalidates MAC membership on this second call, and keeps
   its uniqueness checks. A device list is a candidate list, not a registration
   authorization token; the backend remains authoritative after key revocation
   or concurrent registration. Report 409/422 honestly without auto-retry.
5. Require an explicit successful registration acknowledgement and station ID.
   Show registration received, without claiming chain activation, ingestion or
   rewards. No use of legacy /api/v1/stations/provision, whose registry is a
   different path. No oracle submit, collector or earnings display changes.

The API/application keys live only in the screen's short-lived controllers and
an in-memory verified-account capability. Obscure the fields; disable suggestions
and autofill, opt out of Android keyboard learning; do not persist or log them. Use static mapped errors, never raw
Dio/request/response exception text. Clear credentials/candidates on pause,
dispose, flag withdrawal, identity change, or success. Cancel pending requests
and reject late results with a generation check. A new credential edit removes
the verified selection. Registration cannot combine one account's verified
MAC with another key pair. Do not echo full MACs in the UI or diagnostics.

Ecowitt #822 is a concrete server-side SSRF history. This phone flow has no host,
subnet, redirect or ecowittHosts input, no LAN HTTP probes and no generic
discovery/provision call. Any future Ecowitt LAN work needs bounded on-device
discovery plus a separately approved ownership proof. Server-side arbitrary
private-host fetching must not return. Neither device discovery nor a local
MAC reply can substitute for the Ambient account-membership check.

## Delivery and checks

Use the existing default-off flag; the guarded screen enforces it as well as
the entry point. Replace the misleading no-op dashboard banner with an explicit
Ambient entry. Keep the older protocol helper unused for future separate work;
do not claim it is wired. Add a dedicated feature repository/screen under
`features/collector/`; navigate from the existing PWS screen without changing
shared app-router routes. No new packages, native permissions or platform SDKs.

Tests use production ApiClient/repository and a captured in-memory Dio transport
with synthetic account keys, MACs and coarse coordinates. Cover flag-off zero
requests, exact backend paths/payloads, authentication refusal, malformed/empty
device lists, masked selection, edit invalidation, MAC membership, missing
acknowledgement, 409/422 errors, pause/disposal late-result rejection and mounted
entry in empty/error station states. Main must fail the new reachable-entry
control; mutations must expose a wrong route or missing MAC/flag boundary.
Run cached dependencies only, analysis and a memory-gated full Flutter suite,
sequentially with concurrency=2. No real account, LAN, BLE or hardware probe.

Release: app-tier r19, default off. Backend routes already exist; their deployment
reachability and hardware/account runtime remain unverified by this lane. The
complete BLE/LAN auto-discovery readiness item is PARTIAL after this Ambient
account onboarding slice; it must not be marked fully delivered.
