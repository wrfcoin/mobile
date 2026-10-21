# Ecowitt LAN onboarding: after-launch design

Refs #72. Companion work: infrastructure support for station onboarding.
Round 13 SOL-K, 2026-10-02. Status: DESIGN ONLY; implementation is not authorized.

The owner selected Ambient at launch and other brands after launch. This note
proposes an Ecowitt phone path for already configured gateways on the user's
Wi-Fi. It adds no application code, backend adapter, endpoint, permission,
deployment setting or release flag. It is not an r19/GO admission record.

## Verified starting point

Source snapshots, not deployed behavior:

| Repository / head | Evidence |
| --- | --- |
| mobile `3edec1929030190311c9f0da29e370ce4f7f95f9` | `lib/services/pws/pws_discovery_provider.dart:15-23` still injects no-op scanners; its `_ecowitt._tcp.local` comment is not manufacturer support evidence. `lib/core/feature_flags/feature_flags.dart:43-47` limits the existing default-off flag to Ambient account onboarding. `lib/features/collector/data/repositories/ambient_onboarding_repository.dart:106,169` uses authenticated account verification and registration. |
| backend `595ce35164f62d7812d2ebba852d588cf99b6c43` | `server/services/station-registration-service.ts:162-173,525-528` keeps Ecowitt pending and refuses its submitted MAC with 422 `MAC_PROVIDER_UNVERIFIED`. Lines 544-557 verify Ambient account MAC membership; 646-693 enforce canonical MAC locking and active-station uniqueness. |
| Same backend head | `server/routes/station-discovery-routes.ts:396-424,469-510,545-552` contains host/subnet discovery and a redirect-aware HTTP probe. Those legacy operator surfaces are not the proposed phone registration path. |

The earlier backend review recorded an unauthenticated arbitrary-host/subnet
SSRF problem. Later controls do not make
that server-side probing suitable for a public phone flow. The proposal never
sends a LAN destination, subnet, proxy URL or gateway configuration to WRFCoin.

## Manufacturer evidence and limits

The [vendor TCP protocol](https://osswww.ecowitt.net/uploads/20211104/WN1900%20GW1000%2C1100%20WH2680%2C2650%20telenet%20v1.6.3%20.pdf)
describes same-WLAN UDP command `0x12`, port 46000, and replies containing a
MAC, address, port and SSID (PDF pp. 11-12). It also describes a TCP gateway at
45000 and MAC-read command `0x26`. These are identification/configuration
interfaces; the note makes no claim that their replies authenticate ownership.

The [vendor HTTP protocol](https://oss.ecowitt.net/uploads/20260109/HTTP%20API%20interface%20Protocol%20%28Generic%29-%28V1.0.5-2025-10-08%29%20.pdf)
documents local `get_livedata_info` and `get_network_info`. Some network/server
settings responses include Wi-Fi or service credential fields. The proposed
first phone slice does not fetch those HTTP settings or upload their contents.

The [GW1100 manufacturer guide](https://shop.ecowitt.com/en-gb/collections/console-or-gateway/products/gw1100)
describes local browser setup and adding a gateway to an Ecowitt account by
MAC. Its local login password can initially be unset. A setup page, known MAC
or locally reachable gateway therefore cannot be treated as an ownership key.

The [current vendor documentation index](https://www.ecowitt.com/api/quickstart/product?id=107)
links the [official cloud API documentation](https://doc.ecowitt.net/web/).
It also says TCP observation-data support is no longer maintained for new
sensors. Use TCP only for the reviewed discovery/identity subset on qualified
models; cloud ingestion is a separate epic story. No generic mDNS advertisement
or support across every Ecowitt console/firmware is assumed.

The cloud documentation's client-rendered contents were not readable in this
review. A precise account-device endpoint, authentication fields, pagination,
response shape and account-binding semantics remain UNVERIFIED. Do not infer
them from a successful weather-data lookup or hardcode a guessed API path.

## Proposed phone flow and destination confinement

1. Add a separate default-off Ecowitt pairing flag after approval; do not widen
   the existing Ambient flag. Require a signed-in wallet, an explicit user
   action and local-network consent. An already configured supported gateway
   must be on the active Wi-Fi. Initial Wi-Fi provisioning remains in Ecowitt's
   own app/web UI; WRFCoin does not collect router credentials or issue writes.
2. Bind one discovery session to that OS-reported Wi-Fi interface and its
   current address/netmask. Send only the documented discovery command to its
   directed IPv4 broadcast at the protocol port. Proposed bounds: one request,
   three-second window, 32 accepted candidates, 1 KiB maximum datagram. No
   subnet enumeration, manual host box, hostname resolution, cellular/VPN
   fallback, routing across interfaces or persistent background scan.
3. Parse length/checksum/MAC with a strict protocol schema. Reject malformed or
   oversized packets before allocation. A reply's advertised address and port
   never choose a destination. Admit only an observed sender on this interface's
   directly connected RFC1918 subnet; exclude self, subnet network/broadcast,
   loopback, link-local/metadata, multicast, public and IPv6 addresses. Discard
   the SSID. These limits constrain network access, not proof of identity.
4. Show a masked device candidate and require selection. A selected candidate
   is an in-memory capability bound to sender address, interface, MAC and
   session generation. If identity confirmation is needed, use only that
   candidate's observed sender and hardcoded TCP port 45000, MAC-read `0x26`,
   two-second deadline and 1 KiB response cap. No advertised port, redirects,
   DNS, arbitrary command, HTTP fallback or network/settings dump. A differing
   MAC invalidates the candidate; a LAN attacker could still spoof both replies.
5. Collect Ecowitt account credentials in ephemeral obscured fields. Through
   the fixed authenticated WRFCoin API, ask the future backend to enumerate
   the credential owner's account devices. Intersection with the selected LAN
   MAC is required. Client-discovered metadata is never authoritative for
   membership. Nothing is sent to WRFCoin about the candidate's IP or SSID.
6. Collect name and manual coordinates; validate then round to 0.1 degrees on
   the phone and server. Do not import vendor precise coordinates. Register
   the selected account MAC through the ownership procedure below. Show
   registration received only after an explicit acknowledgement. Activation,
   ingestion and reward eligibility each require their own deployed evidence.

Pause, logout, credential edit, flag withdrawal, permission loss, interface
change and disposal cancel sockets/requests and invalidate the generation.
Discard late packets and responses even if cancellation races with completion.
Proposed candidate and verification lifetimes are at most five minutes, with
fresh membership validation at final registration. A missing native permission,
interface capability or supported model produces an honest unavailable result.

## Ownership proof equivalent to Ambient's account MAC check

The admission predicate is: authenticated wallet W controls vendor credentials
K; a freshly authenticated vendor account-device enumeration under K contains
canonical MAC M; the registration binds M to W atomically; M is not bound to a
different active station. LAN visibility is optional identity assistance and
never satisfies any part of the vendor-account authorization predicate.

This matches Ambient's current account-membership assurance, not a hardware
signature, purchase receipt or theft-proof device attestation. Vendor manuals
describe adding devices by MAC, so whether the vendor prevents adding another
person's MAC, and whether credentials scope the returned list to that account,
must be established before authorizing this adapter. If possession of a known
MAC alone can create account membership, label that weakness and keep admission
unavailable pending owner/security review; do not call it an equivalent proof.

The backend adapter, in a future separately authorized PR, must:

- Use only a server-defined HTTPS vendor origin and reviewed account-device
  operation from the official API. Accept no URL/host/subnet override, disable
  redirects, restrict actual resolved destinations and enforce request/response
  size/time/page bounds. Reject malformed, truncated or incomplete lists and
  accounts with no matching device. Public reading access is insufficient.
- Derive W from the existing authenticated wallet session. Never accept an
  owner address, operator token or admin override from the phone's payload.
  Validate M as a six-byte ASCII MAC before canonicalization; use the same
  separator/case-equivalent identity on every admission, retention and update.
- Re-enumerate membership at final admission and credential rotation. An
  opaque short-lived verification handle may hold transient credentials on the
  server, bound to W/M/provider/generation; it cannot replace revalidation.
  Reject expired/replayed/cross-wallet handles and ambiguous device selection.
- Finish vendor requests before SQL locks. In one checked-out transaction,
  retain the existing owner-first lock order and MAC namespace 1261, enforce
  one MAC per active station, bind credentials and commit registration.
  Same owner/same station is idempotent; another station, including one owned
  by that wallet, receives a conflict. Vendor outage refuses admission.
- Generalize the uniqueness query as well as reusing the lock: today's SQL at
  682-687 filters Ambient rows. A reviewed identity mapping must cover Ecowitt
  and brand aliases for the same physical gateway, including old Ambient rows,
  before Ecowitt can activate. Provider-tag changes must not release a device
  reservation or create a second earning identity.
- Keep MACs access-restricted and absent from anonymous projections. Encrypt
  accepted provider credentials at rest for the future collector; discard
  transient credentials on expiry/failure. Credential rotation must prove
  membership of the retained MAC even when a request omits it. Provider change,
  ownership transfer/recovery and historical pending rows need explicit policy;
  vendor re-addition never silently replaces an active owner.

Proposed API operations are account verification and final station admission,
using fixed WRFCoin routes chosen by the backend owner. They do not exist for
Ecowitt today. The legacy discover/provision/status registry is not an
ownership capability and is not used. Until the adapter, uniqueness migration
and live ingestion are reviewed, retain `MAC_PROVIDER_UNVERIFIED` and pending
status. This document does not flip `LIVE_INGESTION_PROVIDERS`.

## Privacy, platform and ingestion boundaries

Keys and verification handles are not logged, echoed, placed in query strings
at the WRFCoin boundary, persisted on the phone or sent to LAN devices. Hide
keyboard suggestions/autofill/learning; clear screen state on the lifecycle
events above. Use static mapped errors rather than raw network exceptions.
Raw vendor/UDP/TCP payloads, MACs, LAN addresses and SSIDs never enter crash
reports, telemetry or public station/map data. Exact station coordinates do not
leave the entry flow; store/transmit only validated 0.1-degree values.

Future native work must qualify Android's actual selected APIs and target SDK
against [Android Wi-Fi permission guidance](https://developer.android.com/develop/connectivity/wifi/wifi-permissions).
The required nearby-device/location permission varies by API; do not infer it
from raw socket support or harvest Wi-Fi identifiers to infer location.
For iOS, [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
requires local-network access for outgoing LAN traffic and a multicast
entitlement for UDP broadcast. Owner signing/entitlement access and denial/
revocation tests are release prerequisites. Bonjour service declarations apply
only if a later reviewed design actually uses Bonjour. No BLE is proposed.

Gateway custom HTTP uploads, a plaintext shared passkey or a challenge returned
over unauthenticated LAN transport do not replace account-membership proof.
Direct internet HTTP uploads carrying provider/WRFCoin credentials are not
proposed. A later cloud adapter owns reading freshness, canonical units,
anti-replay, credential rotation and outage behavior. Pure offline/LAN ingestion
would need a separate authenticated relay/attestation design and owner ruling.

## Future acceptance and release gates (all unexecuted)

| Boundary | Required falsifiers / evidence |
| --- | --- |
| Flag, consent and lifecycle | Flag off or permission denied gives zero packets/provider requests; pause/interface change/logout cancels work; late replies cannot register. |
| Network confinement | Reject metadata/link-local/loopback/public/off-interface sender, spoofed advertised IP/port, hostname/URL input, malformed length/checksum, over-limit response, redirects and any write command; backend never contacts a LAN destination. |
| Account proof | A real-shaped recorded account list contains M; list from another account, public data lookup, revoked key, nonmember M, empty/truncated list, forged handle or omitted retained M refuses. No test with real keys. |
| Atomic uniqueness | Real two-connection transaction controls: same M/case/separator and cross-brand alias race yields one binding; same station remains idempotent; another station gets conflict; rollback retains no partial credentials. |
| Privacy | Keys/MAC appear only in designated authenticated account/admission requests and restricted backend records (keys encrypted at rest). LAN requests contain no keys; phone storage, logs/crash export and anonymous projections contain no keys, full MAC or LAN topology. No transmitted/stored location is finer than 0.1 degrees; check errors and all delayed-result paths. |
| Honest release | Pending/unmounted/unsupported/offline/outage states cannot imply pairing, active ingestion, chain activation or rewards. |

Before implementation: obtain a versioned official cloud contract with account
scope semantics, sanitized synthetic fixtures and a supported model/firmware
matrix; choose owner transfer/recovery and alias policies; review this design.
Then separate backend ownership/ingestion, mobile/native discovery and frontend
brand-selection PRs. Each needs production-boundary RED-first regressions and
mutations, canonical local/runner evidence, privacy/abuse review and hardware
QA authorized by the owner. Native permission/real gateway/cloud behavior is
RUNTIME-UNVERIFIED here. No runtime or future test success is claimed.

Owner inputs for later work: initial hardware/OS cohort, documented free vendor
API/account-binding contract, ingestion choice (recommend account-scoped cloud
adapter first), transfer/recovery and alias rules, iOS signing capability,
backend encryption/retention/rate budgets and release date after launch. Request
credential references through the normal secure process, never key values in
the ledger. Missing inputs block implementation, not completion of this note.
