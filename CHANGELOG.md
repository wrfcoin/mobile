# Changelog

All notable changes to `wrfcoin_mobile` are recorded here.

## [Unreleased]

### Changed

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
