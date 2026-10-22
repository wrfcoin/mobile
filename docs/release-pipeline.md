# Mobile Release Pipeline

This repository now ships releases through Fastlane-backed iOS and Android jobs.
The workflow validates versioning and release notes before it attempts to sign or
upload anything.

## What the pipeline does

- Validates that `pubspec.yaml` already carries the intended semantic version.
- Requires a matching changelog section in `CHANGELOG.md`.
- Pulls iOS signing assets through Fastlane Match.
- Reads Android signing material from GitHub Actions secrets only.
- Builds a release IPA and Android App Bundle.
- Uploads iOS builds to TestFlight and Android builds to the Play Store internal track.
- Writes checksum metadata for each release artifact under `build/release/`.
- Verifies selected beta-release secrets and Android internal-track routing in preflight
  before any signing, build, or upload job starts.

## Required secrets

### iOS

- `WRFCOIN_IOS_BUNDLE_IDENTIFIER`
- `WRFCOIN_IOS_TEAM_ID`
- `MATCH_GIT_URL`
- `MATCH_PASSWORD`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_BASE64`

### Android

- `WRFCOIN_ANDROID_KEYSTORE_BASE64`
- `WRFCOIN_ANDROID_KEYSTORE_PASSWORD`
- `WRFCOIN_ANDROID_KEY_ALIAS`
- `WRFCOIN_ANDROID_KEY_PASSWORD`
- `PLAY_SERVICE_ACCOUNT_JSON_BASE64`

## Versioning rules

- Keep `pubspec.yaml` in the form `x.y.z+build`.
- Use `bundle exec fastlane bump_version` to stage a local release bump.
- The release workflow refuses to run if the semantic version in `pubspec.yaml`
  does not match the requested release version.
- The build number can come from `BUILD_NUMBER` or the GitHub Actions run number.

## Changelog rules

- Add a release note section to `CHANGELOG.md` for the version being shipped.
- The release context check looks for a heading matching the semantic version.
- Keep the notes concise and user-facing. The workflow uses them as the TestFlight changelog.

## Release flow

1. Bump `pubspec.yaml` with `bundle exec fastlane bump_version`.
2. Add a matching section to `CHANGELOG.md`.
3. Push the branch and run `mobile-release.yml` from GitHub Actions.
4. Confirm the preflight job verifies the selected TestFlight/internal-track secrets.
5. Confirm the iOS and Android jobs both finish and inspect the uploaded checksums.

## Rollback

- iOS: stop external distribution in App Store Connect and ship a follow-up build.
- Android: halt the internal track rollout or promote a newer build on top.
- Keep the release metadata JSON from `build/release/` so the exact artifact hash stays auditable.

## Sideload profile APK (testnet dogfooding, zero cost)

For testing on physical devices (#44) without a store or a release keystore, build a
debug-signed **profile** APK:

```bash
export ANDROID_HOME=$HOME/Android/Sdk   # command-line tools + platform + build-tools
export JAVA_HOME=/path/to/jdk-17        # a full JDK with javac, not a JRE
scripts/build_profile_apk.sh https://<tailnet-host>/api

# Tailnet full-API route (infra#1062, mobile#44): the API is on :9444 but the
# backend signs wallet-login challenges for the portless funnel origin.
WRFCOIN_WALLET_AUTH_ORIGIN=https://<tailnet-host> \
  scripts/build_profile_apk.sh https://<tailnet-host>:9444/api
```

`WRFCOIN_WALLET_AUTH_ORIGIN` must equal the backend's `WRFCOIN_WALLET_AUTH_ORIGIN`. When it is
unset the app derives the login origin from the API URL (`scheme://host[:port]`), so the script
refuses an API URL with an explicit port unless the origin is set. A set origin must be a bare
https origin (no path, query or trailing slash) that passes the same host gate as the API URL.

The script refuses, before building:
- an API URL that fails the shared release gate, `scripts/validate-release-api-host.sh`. It
  requires https and a canonical, multi-label public DNS name that resolves to a non-loopback
  address. It rejects IP literals in every spelling (`127.1`, `0x7f.1`, `[0:0:0:0:0:0:0:1]`),
  `localhost` in any case or with a trailing dot, and reserved suffixes such as `.local`,
  `.localhost`, `.invalid` and `.test`. It also rejects placeholder hosts. There is no resolver
  test hook in the gate; its tests stub `getent` through `PATH`.
- a missing SDK, a missing or non-executable `apksigner`, or a JDK without `javac`.

It prints the API URL and the wallet-login origin it built with. It caps Gradle at 3 GB with the daemon off and unsets the `WRFCOIN_ANDROID_KEYSTORE_*`
variables. It restores the `android/gradle.properties` rewrite made by Flutter's migrator. It
prints the APK path, size and sha256, then `PROFILE_APK_OK`, only after `apksigner` confirms
exactly one signer, the Android Debug cert.

Gate tests (no SDK or network needed): `scripts/test-release-api-host-gate.sh` and
`scripts/test_build_profile_apk_gate.sh`.

Profile mode is deliberate: release mode needs `TLS_SECURITY_PROFILE=public-release` and TLS
pins, and it is fatal at startup without them. The debug cert belongs to each machine, so
this APK is for sideloading only. Never publish it. Installing a build from another machine
means uninstalling the current one first.

## Security notes

- Do not commit signing keys, certificates, provisioning profiles, keystores, or Play service account files.
- Do not hardcode Apple IDs or team IDs in the workflow.
- Keep Match credentials private to the repository secrets store.

## Required signing chain

Set `WRFCOIN_CHAIN_ID=888` for the post-cut testnet release and verify the
owner-published genesis hash `553a3758386d9631037d7469686acb4a121ced81dcf5cde256e2d05667c5f332` before distribution. Fastlane
requires the chain value; direct release compilation also refuses an unset or
empty chain define. Use `--dart-define=WRFCOIN_CHAIN_ID=888` for direct builds.
