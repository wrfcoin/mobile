# WRFCoin Mobile

WRFCoin Mobile is a Flutter app for testnet wallets and contributing weather observations from a phone.

## Public testnet

Public launch: **2026-10-22**. This is a test network. It may be reset without notice. Balances and tokens have no monetary value. No migration to mainnet is promised or implied. Please attach no production bridges, exchange listings or irreplaceable assets.

- [WRFCoin website](https://wrfcoin.com)
- [Start with the quickstart](https://github.com/wrfcoin/docs/blob/main/testnet/quickstart.md)
- [Help and bug reports](https://github.com/wrfcoin/testnet-support)
- [Security reporting](SECURITY.md)

[Read the facts page](https://github.com/wrfcoin/docs/blob/main/testnet/facts.md).

The Android APK is **not yet published**. Signing and distribution follow launch; see the [release recipe](docs/RELEASING.md). Source-build capabilities below do not establish device acceptance or a signed release.

## Today (testnet build)

- **Wallet:** create or import a wallet, view balances and transaction history, and keep signing keys on the client.
- **Send and receive:** share a receive address and sign testnet transfers. Send availability depends on the build configuration and backend capabilities; legacy addresses are receive-only.
- **Phone-as-a-station:** register a phone station and submit signed sensor observations, subject to device sensors, permissions and station setup.
- **Earnings:** view backend-reported reward totals and role earnings; missing evidence stays unavailable, and a submitted observation is not a guaranteed payout.
- **Leaderboard:** browse the contribution leaderboard returned by the API.

These screens depend on the configured testnet API. An unavailable service or unsupported sensor is not replaced by a promise of live data.

## Planned

Environmental AR overlays, severe-weather expert alerts, AI-validated imagery rewards, and stealth-wallet/zero-knowledge privacy are **not launch capabilities**. Experimental screens and supporting code do not establish those products. Forecast accuracy and reward eligibility require separate validation.

## Build and run

Use Flutter stable and a configured Android development device or emulator. From this repository:

```sh
bash scripts/ci_pub_get.sh
flutter run
```

Debug builds default to a local development API. See the configuration below for an explicit endpoint, [CONTRIBUTING.md](CONTRIBUTING.md) for checks, and [docs/RELEASING.md](docs/RELEASING.md) for release prerequisites.

## Tech stack

Flutter and Dart, Riverpod state management, and HTTP APIs with client-side signing.

## 📁 Project Structure
```text
mobile/
├── android/            # Android native code
├── ios/                # iOS native code
├── lib/
│   ├── bootstrap/      # Application startup
│   ├── core/           # Shared application infrastructure
│   ├── features/       # Feature modules
│   ├── services/       # API and platform services
│   ├── app.dart        # Application widget
│   └── main.dart       # Entry point
├── scripts/            # Development and CI checks
└── test/               # Automated tests
```

## Release API configuration

Release builds are produced by the Fastlane lanes (`fastlane/Fastfile`, `release_dart_defines`), which turn these environment variables into `--dart-define`s:

| Variable | Required | Dart define | When unset |
|---|---|---|---|
| `WRFCOIN_API_BASE_URL` | yes | `API_BASE_URL` | the release fails (see below) |
| `WRFCOIN_TLS_PIN_SHA256_CURRENT` / `_NEXT` | current: yes; next: no | `TLS_PIN_SHA256_CURRENT` / `_NEXT` | the release fails (current) / no next pin |
| `WRFCOIN_WALLET_AUTH_ORIGIN` | no | `WRFCOIN_WALLET_AUTH_ORIGIN` | no define: ed25519 login expects the origin of `API_BASE_URL` |
| `WRFCOIN_CHAIN_ID` | yes | `WRFCOIN_CHAIN_ID` | release/profile compilation fails |
| `WRFCOIN_NETWORK_ID` | no | `WRFCOIN_NETWORK_ID` | no define: `testnet` |

These wallet-auth variables must equal the backend's wallet-auth origin, chain ID and network, or ed25519 login refuses the challenge. `WRFCOIN_WALLET_AUTH_ORIGIN` must be the **canonical** origin, the exact string `Uri.parse(origin).origin` (and the backend's `new URL(origin).origin`) returns: `https://host[:port]`, lowercase host, no path or trailing slash, and no port unless it is non-default. So `https://Auth.Example.test`, `https://host:443` and `https://host:0443` are refused; use `https://auth.example.test`. A port must be 1–65535 without leading zeros. `WRFCOIN_CHAIN_ID` is a positive integer no larger than 2^53−1 (the backend compares it as a JavaScript safe integer). `WRFCOIN_NETWORK_ID` matches `[A-Za-z0-9._-]{1,64}`. Fastlane rejects malformed values and requires the chain ID. Direct release and profile builds also fail compilation when the chain define is unset or empty.

The public testnet API hostname is an **open owner decision**; this repository does not choose or imply one. Release builds fail closed until `WRFCOIN_API_BASE_URL` is explicitly set to a resolvable, non-placeholder HTTPS endpoint. Debug builds with no define use `http://localhost:4001/api`; developers may supply another explicit local URL with `--dart-define=API_BASE_URL=...`.

### ed25519 wallet login configuration

An ed25519 (first-party) wallet signs a login challenge only after checking that it names this build's expected relying-party origin, chain and network, and that its `Expiration Time` is still in the future on the device clock. Otherwise the login fails closed and nothing is signed.

- **`WRFCOIN_WALLET_AUTH_ORIGIN`** (`--dart-define=WRFCOIN_WALLET_AUTH_ORIGIN=https://<host>`) is the origin the challenge must name in its `URI:` and host lines. It must equal the backend's `WRFCOIN_WALLET_AUTH_ORIGIN` exactly (scheme, host, optional port, no path).
  - When it is unset, the app uses the origin of `API_BASE_URL`. That is correct when the testnet edge serves `/api` on the same public origin the backend signs into its challenge.
  - The release lane (`fastlane/Fastfile` `release_dart_defines`) passes this define only when the `WRFCOIN_WALLET_AUTH_ORIGIN` environment variable is set (see the table above). Otherwise release builds rely on that fallback. If the API is ever served from a different origin than the wallet-auth origin, set it for the release, or login will refuse.
- **`WRFCOIN_CHAIN_ID`** / **`WRFCOIN_NETWORK_ID`** (release/profile chain required / network defaults to `testnet`) are the same values transfers are signed for. They must match the backend's wallet-auth chain ID and network. The release lane always passes the required chain ID. See [release chain controls](docs/SIGNING_CHAIN_BUILD.md) for direct builds and compile checks.

## 🤝 Contributing
Please check the [Issues](https://github.com/wrfcoin/mobile/issues) tab for current tasks and discussions.

### Dependency Upgrade Policy

Patch-version bumps (e.g. `12.0.2 → 12.0.3`) may be merged without review if all CI tests pass — Dependabot PRs for patch versions are auto-merged. Minor-version bumps require a brief PR description noting any API changes and confirming `flutter analyze` is clean. Major-version bumps (e.g. `riverpod 2 → 3`, `share_plus 9 → 10`) require a dedicated issue, a migration branch, and at least one reviewer sign-off before merging. Never accept a major-version upgrade bundled with feature work.

## License

Licensed under MIT OR Apache-2.0; see [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE).
