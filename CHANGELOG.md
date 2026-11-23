# Changelog

All notable changes to `wrfcoin_mobile` are recorded here.

## [Unreleased]

### Security

- No APK is debuggable any more: the profile build type (which Flutter derives from debug) and release both set `isDebuggable = false`. `scripts/build_profile_apk.sh` refuses a debuggable APK, and CI checks the Gradle file.
- `scripts/build_profile_apk.sh` pins the signing certificate's SHA-256 (the tester debug key) and refuses any other key, so a build from another machine is never handed to a phone it would not upgrade.
- Version 0.1.2, build 3: each published APK gets a higher build number.

### Fixed

- The weather card shows the observed temperature and wind from the latest observation, not the forecast's; when the observation has no reading it shows a dash instead of a forecast number. "Updated" is the observation's time, and the share card gives wind in km/h. Version 0.1.4, build 7.
- A wallet that can't vote on a proposal now says why in plain words: it held less than 1 WRF when the proposal was created (with the block number), and it can vote on proposals created from now on while it holds 1 WRF or more. Version 0.1.3, build 6.
- After a send, the transaction identifier in the receipt is a link: tap it to open the transaction's page on wrfcoin.com (it can take about a minute to show in a block) instead of pasting it into Explore.
- Proposing or voting right after unlocking with the device PIN no longer stops with "Open the app to sign your vote." The PIN screen pauses the app and the unlock finishes a moment before the app is back on screen; the app now waits up to 3 seconds for it, and refuses only if it really is not back, saying the proposal or vote was not signed and nothing was sent. Version 0.1.3, build 5.

### Added

- Approve this phone (Station security): a station owner can approve this phone's collect key as the one device that may send the station's readings, or clear it. Signed with the owner's wallet key on this phone. Shown only as "not active on the network yet" until the backend's `/ownership` reports `features.stationSubmitterKey: true`, and the service refuses to send it before then. Version 0.1.4, build 7.
- Collect asks the station registrar to register this phone's station, only once the network lists `station_registrar_key` as active and the registrar answers.
- Vote on advisory proposals in the app: Vote For / Vote Against on an open proposal, a sheet that says exactly what is signed (proposal, choice, wallet, network), then the device unlock. Signed with the app's own wallet key (core4 `advisory_action_message`, byte-identical to the website, pinned by core4's vectors); the recovery phrase is never shown or asked for. Says plainly why a wallet can't vote (held under 1 WRF when it was proposed, already voted, voting closed). The "Vote on wrfcoin.com" button is gone. After sending it says the vote counts once it is in a block (about 77 seconds) and reads the chain again; if the relay's answer is lost after sending, it says the vote may still count and waits for the chain read instead of saying it failed. Version 0.1.3, build 4.
- New advisory proposals from the app: "New proposal" on the governance list, a title and text with live byte counters (160 / 1024 bytes, the website's and core4's text rules), a confirm sheet that says "Proposing holds 1 WRF from this wallet...", then the device unlock. Same signer and relay as the vote (byte-identical to the website's propose, pinned by core4's vectors). Refused before the unlock when the wallet has under 1 WRF (the advisory transaction pays no fee); relay refusals (already has an open proposal, chain full, rate limited) in plain words.
- Sky View: a full-screen sky map that follows the phone, drawn with no camera and no network. Stars, planets, Sun, Moon, grid and horizon; Android's fused rotation-vector sensor with an accelerometer/magnetometer fallback; automatic declination from WMM2025; "Align on a star" calibration.
- Contacts: named addresses ("Send to Mom") saved on this phone only, with add, rename, remove, pick-a-contact in Send, and import/export as a JSON file. Imported contacts are never allowed for sending until you allow them.
- Send allowlist (opt-in): when on, Send refuses anyone who is not an allowed contact. Turning it on is instant; turning it off, or allowing a new contact while it is on, waits 24 hours.
- Back up / view recovery phrase behind a plain warning, a typed confirmation and the device unlock.

### Changed

- The backup reminder on the wallet screen is calmer and links to the backup screen. The recovery phrase is a cold backup: sign-in, balance and sending never ask for it.

- The wallet reads its balance from the public route `GET /api/public/balance/0x<address>` and shows "Earned in total" beside it. A switched-off read (404) shows "Unavailable", a rate-limited one (429) "Busy"; a missing total is never shown as zero.
- Release TLS pinning now pins a CA public key (SPKI SHA-256 of the issuing intermediate or its root) instead of the leaf certificate, so Cloudflare's 90-day leaf renewals no longer lock out installed apps. See docs/RELEASING.md#tls-pins.
- Debug builds default to chain 888; the testnet notice links to https://wrfcoin.com/testnet-disclaimer.html.

## 2026-10-22 public testnet launch

### Added

- Testnet wallet creation/import, receive addresses and client-signed transfers.
- Phone station registration and signed sensor observation submission.
- API-backed earnings and contribution leaderboard screens.
- Public support and security-reporting guidance.
- Android release build and checksum instructions; signed APK not yet published.

## [0.1.0] - 2026-04-11

- Establish the Fastlane release pipeline, signing hooks, and version gating.
- Validate release version, changelog presence, and signing secrets before upload jobs.
- Emit checksum metadata alongside iOS and Android release artifacts.
