# Public testnet Android APK release preparation

This is a build and verification recipe for launch issue #443. It does not publish
an artifact or establish device acceptance. Testnet WRF has no monetary value.

## Current state and target

At main `ac00c7e`, `ApiConstants.baseUrl` has an empty `API_BASE_URL` default.
Release mode has no localhost fallback. The release workflow injects
`WRFCOIN_API_BASE_URL` from repository variables or secrets; its configured value
is not established by source inspection. The existing tester profile build is
configured for a private API route, so it is not the public launch artifact.
No GitHub Release was present when this guide was prepared (2026-10-19).

The launch APK must use the public API, initially proposed as
`https://wrfcoin.com/api`. The website being reachable does not establish that all
mobile endpoints work there. The release owner must verify wallet login, faucet,
balances and transfers from outside the private network before selecting that
URL. A publicly reachable funnel origin is also allowed, provided the complete
API and the backend's wallet-login origin match the configuration. Do not use a
private-only API port. An HTML response or redirect to the homepage is not API
acceptance.

`WRFCOIN_WALLET_AUTH_ORIGIN` must equal the backend's configured login origin,
including its port if any, with no path or trailing slash. It need not equal the
API origin when the backend deliberately uses a separate login origin. Record
both explicitly. The release/profile chain ID is required; the network defaults to `testnet`.
Confirm both against the selected deployment. Direct Flutter release and profile builds
refuse an unset or empty chain define at compilation, as does Fastlane.
See [release chain controls](SIGNING_CHAIN_BUILD.md).

## Build path and prerequisites

- Android has one application ID, `com.wrfcoin.wrfcoin_mobile`, and no product
  flavors in `android/app/build.gradle.kts`. Use `flutter build apk --release`,
  without `--flavor`, for a universal sideload APK.
- The existing [release pipeline](release-pipeline.md) and `fastlane/Fastfile`
  build an Android App Bundle and upload to a store track. Do not dispatch that
  workflow for this preparation-only task. The profile helper creates a
  debug-signed tester APK; do not distribute it as the release.
- Use an isolated build worker with JDK 17, Android SDK/platform/build-tools
  required by the selected Flutter revision, and `apksigner` on PATH.
  `android/gradle.properties` requests an 8 GB Gradle heap plus up to 4 GB
  metaspace and 512 MB code cache. Allow additional headroom for Flutter/Kotlin
  and the OS. Do not build on the shared workstation under the 4 GB limit.
- Freeze the full source SHA and exact Flutter framework revision before the
  build. CI currently selects the moving stable channel; that alone is not a
  reproducible toolchain pin. Preserve `pubspec.lock`, Gradle wrapper and build
  files from the selected source; record Flutter/Dart, JDK, SDK and build-tools
  versions in the build record. Repeat with those same inputs. This recipe does
  not promise bit-for-bit equality across machines.
- The owner supplies the release version/build number, changelog entry, and all
  signing inputs through the worker's secret injection. Gradle falls back to
  debug signing if any signing input is absent: the checks below must run.
- The owner supplies the current TLS **leaf certificate DER SHA-256** fingerprint
  for the API endpoint (not an SPKI pin), and optionally a distinct next pin for
  certificate rollover. Validate them through the deployment's trusted process.
  Do not copy a sample pin or treat format validation as proof of server identity.

## Reproducible build recipe

Run from a clean, isolated checkout of the approved source. Do not enable shell
tracing or dump the environment. Export all required variables privately before
running this block; no keystore, passwords or secret files belong in Git.
`RELEASE_SOURCE_SHA` and `RELEASE_FLUTTER_REVISION` must be full commit IDs.
`RELEASE_VERSION` must match the selected `pubspec.yaml` and changelog;
`RELEASE_BUILD_NUMBER` must be a new positive integer selected by the owner.

```bash
set -euo pipefail
set +x
: "${RELEASE_SOURCE_SHA:?approved full source SHA required}"
: "${RELEASE_FLUTTER_REVISION:?approved Flutter framework revision required}"
: "${RELEASE_VERSION:?release version required}"
: "${RELEASE_BUILD_NUMBER:?new build number required}"
: "${WRFCOIN_API_BASE_URL:?verified public API URL required}"
: "${WRFCOIN_WALLET_AUTH_ORIGIN:?backend login origin required}"
: "${WRFCOIN_TLS_PIN_SHA256_CURRENT:?verified leaf certificate pin required}"
: "${WRFCOIN_ANDROID_KEYSTORE_PATH:?private absolute keystore path required}"
: "${WRFCOIN_ANDROID_KEYSTORE_PASSWORD:?injected signing password required}"
: "${WRFCOIN_ANDROID_KEY_ALIAS:?injected signing alias required}"
: "${WRFCOIN_ANDROID_KEY_PASSWORD:?injected key password required}"
: "${WRFCOIN_CHAIN_ID:?confirmed chain ID required}"
: "${WRFCOIN_NETWORK_ID:?confirmed network ID required}"
test "$(git rev-parse HEAD)" = "$RELEASE_SOURCE_SHA"
test -z "$(git status --porcelain --untracked-files=no)"
test -f "$WRFCOIN_ANDROID_KEYSTORE_PATH"
[[ "$WRFCOIN_ANDROID_KEYSTORE_PATH" = /* ]]
[[ "$RELEASE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]
command -v apksigner >/dev/null
command -v javac >/dev/null
mkdir -p build/release
flutter --version --machine > build/release/flutter-version.json
python3 - <<'PY'
import json, os, re
from urllib.parse import urlsplit
with open('build/release/flutter-version.json') as f:
    assert json.load(f)['frameworkRevision'] == os.environ['RELEASE_FLUTTER_REVISION']
with open('pubspec.yaml') as f:
    version = next(line.split(':', 1)[1].strip() for line in f if line.startswith('version:'))
assert version.split('+')[0] == os.environ['RELEASE_VERSION']
origin = os.environ['WRFCOIN_WALLET_AUTH_ORIGIN']
u = urlsplit(origin)
assert u.scheme == 'https' and u.hostname and not u.username and not u.password
assert not u.path and not u.query and not u.fragment
assert origin == 'https://' + u.hostname + ((':' + str(u.port)) if u.port and u.port != 443 else '')
chain = os.environ['WRFCOIN_CHAIN_ID']
assert re.fullmatch(r'[1-9][0-9]*', chain) and int(chain) <= 2**53 - 1
assert re.fullmatch(r'[A-Za-z0-9._-]{1,64}', os.environ['WRFCOIN_NETWORK_ID'])
PY
bash scripts/validate-release-api-host.sh "$WRFCOIN_API_BASE_URL"
bash scripts/validate-release-api-host.sh "$WRFCOIN_WALLET_AUTH_ORIGIN"
bash scripts/validate-release-tls-pins.sh
# Validate the version and changelog (origin and chain/network checked above).
# This validation lane builds and uploads nothing.
RELEASE_VERSION="$RELEASE_VERSION" BUILD_NUMBER="$RELEASE_BUILD_NUMBER" \
  bundle exec fastlane validate_release_context
flutter pub get --enforce-lockfile
flutter build apk --release \
  --build-name "$RELEASE_VERSION" --build-number "$RELEASE_BUILD_NUMBER" \
  --dart-define="API_BASE_URL=$WRFCOIN_API_BASE_URL" \
  --dart-define="WRFCOIN_WALLET_AUTH_ORIGIN=$WRFCOIN_WALLET_AUTH_ORIGIN" \
  --dart-define="WRFCOIN_CHAIN_ID=$WRFCOIN_CHAIN_ID" \
  --dart-define="WRFCOIN_NETWORK_ID=$WRFCOIN_NETWORK_ID" \
  --dart-define=TLS_SECURITY_PROFILE=public-release \
  --dart-define="TLS_PIN_SHA256_CURRENT=$WRFCOIN_TLS_PIN_SHA256_CURRENT" \
  --dart-define="TLS_PIN_SHA256_NEXT=${WRFCOIN_TLS_PIN_SHA256_NEXT:-}"
```

Install the locked Ruby bundle first (`bundle install`, using Ruby 3.3 as in CI).
Inspect `git diff` after the build: Flutter may migrate Android build files. A
migration is a new input to review, not something to silently discard or ship.
Retain the selected source SHA, dependency lock hashes, public URL/login origin,
chain/network, version/build number and toolchain versions with the artifact.
Never include signing passwords or the keystore in that record.

## Verify signature and checksum before handoff

```bash
set -euo pipefail
apk=build/app/outputs/flutter-apk/app-release.apk
test -s "$apk"
apksigner verify --verbose --print-certs "$apk" > build/release/apk-signature.txt
```

Compare the signer certificate SHA-256 in that report with the owner's expected
release certificate fingerprint from a trusted record. Require the approved
signer set; reject Android Debug certificates or any unexpected signer. APK
signature verification alone does not prove it was signed with the intended key.
Stop before handoff if the comparison fails. Do not confuse this APK signer
fingerprint with the API's TLS certificate pin.

After signature approval, checksum the exact signed bytes:

```bash
set -euo pipefail
artifact="wrfcoin-${RELEASE_VERSION}+${RELEASE_BUILD_NUMBER}-android.apk"
cp build/app/outputs/flutter-apk/app-release.apk "build/release/$artifact"
(
  cd build/release
  sha256sum "$artifact" > SHA256SUMS
  sha256sum --check SHA256SUMS
)
```

On a physical Android device outside the private network, verify startup with
TLS pinning enabled, wallet login, balance loading, faucet and an authorized
testnet send/receive. Check both clean install and upgrade from the supported
prior release, preserving wallet data. Record device/OS, source SHA, artifact
SHA-256 and observed results. A successful compile is not device or public API
evidence. Do not bypass TLS pinning to make this check pass.

Hand the APK, `SHA256SUMS`, source/toolchain record, signature verification and
device results to the release owner. Publishing a GitHub Release and updating
website/download links are separate authorized actions. This guide does not
create a draft release, upload an APK, or change repository settings.

## Unsigned compilation dry run

When the build owner authorizes a workstation with enough memory, compilation
can be checked before release inputs are available. Use a disposable worktree;
this is not a distributable APK and does not establish API or device acceptance.
Keep the signed-release checks above for the eventual release.

The dry run uses reserved `.invalid` origins, a synthetic TLS pin, the current
source version/build number, and provisional testnet chain/network values. It
unsets all four signing variables. Main otherwise falls back to debug signing,
so temporarily replace the release `signingConfig` assignment in
`android/app/build.gradle.kts` with `signingConfig = null`. Record this patch as a
build input; do not commit it or change the signed-release defaults.

Run with JDK 17 and the Android SDK selected through `JAVA_HOME` and
`ANDROID_HOME`; prepend the JDK bin directory to `PATH`. Save the following as
`dry-run.sh` outside the repository and run it from the disposable worktree with
`nice -n 19 /usr/bin/time -v -o dry-run-time.txt bash dry-run.sh`:

```bash
set -euo pipefail
set +x
unset WRFCOIN_ANDROID_KEYSTORE_PATH WRFCOIN_ANDROID_KEYSTORE_PASSWORD
unset WRFCOIN_ANDROID_KEY_ALIAS WRFCOIN_ANDROID_KEY_PASSWORD
flutter pub get --enforce-lockfile
flutter build apk --release --build-name 0.1.0 --build-number 1 \
  --dart-define=API_BASE_URL=https://api.example.invalid \
  --dart-define=WRFCOIN_WALLET_AUTH_ORIGIN=https://login.example.invalid \
  --dart-define=WRFCOIN_CHAIN_ID=777 \
  --dart-define=WRFCOIN_NETWORK_ID=testnet \
  --dart-define=TLS_SECURITY_PROFILE=public-release \
  --dart-define=TLS_PIN_SHA256_CURRENT=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

Record the exact source/toolchain revisions, lock hashes, Flutter migrations,
elapsed time and maximum resident set size reported by GNU time. Its maximum
RSS is not an aggregate peak for concurrent Gradle/Kotlin daemons. Inspect the
APK with `apksigner verify --verbose`: an unsigned artifact must fail signature
verification. Record its SHA-256 and size locally, keep it out of Git, and label
it **UNSIGNED / PLACEHOLDER CONFIGURATION / DO NOT INSTALL OR DISTRIBUTE**.
Restore the temporary Gradle patch and generated migrations after recording
those inputs. A dry-run checksum is not a release checksum.

Before a real release the owner must supply or confirm:

- Approved source and Flutter revisions, version/build number and changelog.
- Public API base URL and backend wallet-login origin, with endpoint acceptance.
- Current API TLS leaf-certificate SHA-256 pin and optional next rollover pin.
- Chain ID and network ID for the selected deployment.
- Signing keystore, alias, injected passwords and trusted signer fingerprint.
- Physical-device acceptance, including clean install and upgrade with wallet
  preservation, followed by approval of the signed artifact and its checksum.
