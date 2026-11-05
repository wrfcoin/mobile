# Public testnet Android APK release preparation

> **Chain 888 testnet:** use chain ID `888`, network `testnet`. The genesis hash, published at launch on 2026-10-22, is `553a3758386d9631037d7469686acb4a121ced81dcf5cde256e2d05667c5f332`; check that the target node reports it before distributing a build. Previous balances and activation heights do not carry over.

This is a build and verification recipe for launch issue #443. It does not publish
an artifact or establish device acceptance. Testnet WRF has no monetary value.

## Current state and target

At main `ac00c7e`, `ApiConstants.baseUrl` has an empty `API_BASE_URL` default.
Release mode has no localhost fallback. The release workflow injects
`WRFCOIN_API_BASE_URL` from repository variables or secrets; its configured value
is not established by source inspection. The existing tester profile build is
configured for a private API route, so it is not the public launch artifact.
No GitHub Release was present when this guide was prepared (2026-10-19).

The launch APK uses the public API at `https://wrfcoin.com/api` (owner decision,
2026-10-31: the API host is https://wrfcoin.com, served through a Cloudflare
tunnel), with `WRFCOIN_WALLET_AUTH_ORIGIN=https://wrfcoin.com`. The website
being reachable does not establish that all mobile endpoints work there. The release owner must verify wallet login, faucet,
balances and transfers from outside the private network before selecting that
URL. A publicly reachable funnel origin is also allowed, provided the complete
API and the backend's wallet-login origin match the configuration. Do not use a
private-only API port. An HTML response or redirect to the homepage is not API
acceptance.

Before building, confirm that the live login challenge names `https://wrfcoin.com`
(through early November 2026 the backend named the older tailnet host, and
an app built for the wrong origin refuses every login):

```bash
curl -s 'https://wrfcoin.com/api/auth/nonce/0x0000000000000000000000000000000000000001?scheme=ed25519' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["message"].split("\n")[1])'
# expect: wrfcoin.com wants you to sign in with your WRFCoin ed25519 account:
```

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
  signing inputs through the worker's secret injection. A release build with
  any signing input absent stops at `preReleaseBuild` with
  `RELEASE_SIGNING_REFUSED`; it never falls back to the debug key. The signer
  checks below must still run.
- The owner sets the TLS **pin set** name, `WRFCOIN_TLS_PIN_SET=cloudflare-universal-v1`
  (a GitHub Actions variable for CI releases). See [TLS pins](#tls-pins). Check
  the live chain against the set before each release. Do not treat a valid
  name as proof of server identity.

## TLS pins

Release builds pin **CA root public keys**, never the leaf certificate.
wrfcoin.com's leaf is a Cloudflare-managed certificate that is replaced about
every 90 days without notice; pinning it would lock out installed apps at each
renewal.

A pin is the SHA-256 of a certificate's DER SubjectPublicKeyInfo, written as 64
hex digits. A release build is compiled with one named **pin set**
(`--dart-define=TLS_PIN_SET=<name>`); the sets are `tlsPinSets` in
`lib/services/api/tls_pin_configuration.dart`. The app accepts a connection only
when the chain the server presents runs, with valid signatures, dates and host
name, from the leaf to a certificate whose key is in the set. The platform trust
store is not used.

dart:io exposes only the leaf certificate to the app, so the app cannot hash
the intermediates itself. Each pin instead selects a root certificate bundled in
`lib/services/api/pinnable_ca_certificates.dart`, and the selected certificates
become the TLS context's only trust anchors. A cross-signed copy of a root that
the server sends (for example GTS Root R4 cross-signed by GlobalSign) has the
same key, so the chain stops at the bundled root.

Fail closed, at three points:

- `scripts/validate-release-tls-pins.sh` (Fastlane and the release workflow run
  it) refuses a missing `WRFCOIN_TLS_PIN_SET`, a name that is not a key of
  `tlsPinSets`, and the retired `WRFCOIN_TLS_PIN_SHA256_CURRENT`/`_NEXT`.
- A public-release app with no set, an unknown or empty set, or a malformed or
  repeated pin stops at start-up.
- A pin that matches no bundled certificate stops the app at start-up, before
  any request.

A debug build with no set uses the platform trust store, as before, and is
labelled NON_RELEASE.

### Why four CAs

wrfcoin.com uses Cloudflare's free Universal SSL. Cloudflare picks the CA, may
switch it without notice, and issues the backup certificate from a different CA
than the primary. It uses four CAs: Google Trust Services, Let's Encrypt,
Sectigo and SSL.com
([certificate authorities](https://developers.cloudflare.com/ssl/reference/certificate-authorities/),
[backup certificates](https://developers.cloudflare.com/ssl/edge-certificates/backup-certificates/)).
An app that pinned one CA would be cut off by a switch, so the set pins the
roots of all four (owner decision, 2026-11-05). Each CA has an ECDSA and an RSA
root; Sectigo is mid-migration from its USERTrust roots to the Public Server
Authentication roots, and both generations have live DV intermediates, so all
four Sectigo roots are pinned. Cloudflare's SSL.com certificates chain through
`Cloudflare TLS Issuing ECC/RSA CA` and `SSL.com TLS Transit ECC/RSA CA R2` to
the SSL.com TLS 2022 roots (Cloudflare's
[cfssl_trust](https://github.com/cloudflare/cfssl_trust) bundle), so the 2016
SSL.com roots are not pinned.

### Pin set `cloudflare-universal-v1`

Each root was downloaded from its CA's own repository (the source below), its
SHA-256 fingerprint matched the Mozilla-derived OS trust store, and the pin was
computed from that DER file. `test/services/api/certificate_pinning_test.dart`
checks every bundled certificate against this table.

| CA | Root | Expires | Source | SPKI SHA-256 pin |
|---|---|---|---|---|
| Google Trust Services | GTS Root R1 (RSA) | 2036-06-22 | https://i.pki.goog/r1.crt | `871a9194f4eed5b312ff40c84c1d524aed2f778bbff25f138cf81f680a7adc67` |
| Google Trust Services | GTS Root R4 (ECDSA) | 2036-06-22 | https://i.pki.goog/r4.crt | `9847e5653e5e9e847516e5cb818606aa7544a19be67fd7366d506988e8d84347` |
| Let's Encrypt | ISRG Root X1 (RSA) | 2035-06-04 | https://letsencrypt.org/certs/isrgrootx1.der | `0b9fa5a59eed715c26c1020c711b4f6ec42d58b0015e14337a39dad301c5afc3` |
| Let's Encrypt | ISRG Root X2 (ECDSA) | 2040-09-17 | https://letsencrypt.org/certs/isrg-root-x2.der | `762195c225586ee6c0237456e2107dc54f1efc21f61a792ebd515913cce68332` |
| Sectigo | USERTrust ECC Certification Authority | 2038-01-18 | http://crt.usertrust.com/USERTrustECCCertificationAuthority.crt | `2021917e98263945c859c43f1d73cb4139053c414fa03ca3bc7ee88614298f3b` |
| Sectigo | USERTrust RSA Certification Authority | 2038-01-18 | http://crt.usertrust.com/USERTrustRSACertificationAuthority.crt | `c784333d20bcd742b9fdc3236f4e509b8937070e73067e254dd3bf9c45bf4dde` |
| Sectigo | Sectigo Public Server Authentication Root E46 | 2046-03-21 | http://crt.sectigo.com/SectigoPublicServerAuthenticationRootE46.crt | `b0b56335468561f5bb9fa12d801784a633a572705d34f32b643445dfa8b005d1` |
| Sectigo | Sectigo Public Server Authentication Root R46 | 2046-03-21 | http://crt.sectigo.com/SectigoPublicServerAuthenticationRootR46.crt | `0e8bb18bbeefb381be21bfc1a206d317298462ad104855f04a0542699708d3d4` |
| SSL.com | SSL.com TLS ECC Root CA 2022 | 2046-08-19 | https://repo-certs.ssl.com/repo/certs/SSLcom-TLS-Root-2022-ECC.der | `1bf00d5c8f13c094dd17e00504cf0888850f12fd067fa1f92c0fdbf60b86e321` |
| SSL.com | SSL.com TLS RSA Root CA 2022 | 2046-08-19 | https://repo-certs.ssl.com/repo/certs/SSLcom-TLS-Root-2022-RSA.der | `2bcf553a66f570900ddd32ba6dfe1ecc06c9182d662dc1b60e1f7b767c2bdd54` |

Sectigo serves its certificate repository over plain HTTP only (its HTTPS
endpoint refuses the handshake), which is why the fingerprint check against the
OS trust store matters for those four.

The first root to expire is ISRG Root X1 (2035-06-04). Ship a set without it,
or with its successor, well before then.

### Check the live chain before a release

```bash
# Save each certificate the server sends as cert1.pem (leaf), cert2.pem, ...
openssl s_client -connect wrfcoin.com:443 -servername wrfcoin.com -showcerts </dev/null 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/{n++} n{print > ("cert" n ".pem")} /END CERTIFICATE/{n=n}'
for f in cert*.pem; do
  openssl x509 -in "$f" -noout -subject -issuer -enddate
  openssl x509 -in "$f" -pubkey -noout \
    | openssl pkey -pubin -outform der \
    | openssl dgst -sha256 | awk '{print "SPKI SHA-256 pin:", $NF}'
done
```

The last certificate's pin (or, for a chain that ends at an intermediate, its
issuer's root) must be in the table above. On 2026-11-05 the chain was leaf,
`WE1`, `GTS Root R4` cross-signed by GlobalSign (pin `9847e565…`), and
`openssl verify -no-CApath -no-CAstore -CAfile <the ten roots> -untrusted
<cert2+cert3> -verify_hostname wrfcoin.com cert1.pem` returned OK, ending at
the bundled GTS Root R4. The pin format is hex; the base64 form
(`openssl dgst -sha256 -binary | base64`) is not accepted.

### Add a CA (or a new root) in an app update

Installed apps only trust the set they were built with, so a new CA has to ship
in an app update **before** Cloudflare can start using it.

1. Download the root as DER from the CA's own repository into a new empty
   directory. Confirm its SHA-256 fingerprint against a second source (the OS
   or Mozilla trust store, or the CA's published fingerprint).
2. Compute the pin from that file:
   `openssl x509 -inform DER -in root.der -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256`.
3. Add the certificate (base64 DER, its source URL, expiry and pin in the
   comment, and its `authority`) to `pinnable_ca_certificates.dart` and to
   `pinnableCaCertificates`.
4. Add a **new** set to `tlsPinSets` (e.g. `cloudflare-universal-v2`) with the
   old pins plus the new one. Keep the `'<name>': [` line shape; the release
   gate script reads it. Never change the pins of a set that has shipped.
5. Update `_bundledPins` and the authority counts in
   `test/services/api/certificate_pinning_test.dart`, and this table.
6. Release with `WRFCOIN_TLS_PIN_SET=<new name>`. Remove a root only after
   every supported app version trusts the CA's replacement.

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
: "${WRFCOIN_TLS_PIN_SET:?TLS pin set name required}"
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
  --dart-define="TLS_PIN_SET=$WRFCOIN_TLS_PIN_SET"
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

The dry run uses reserved `.invalid` origins, the release TLS pin set (the
`.invalid` hosts cannot connect anyway), the current
source version/build number, and provisional testnet chain/network values. It
unsets all four signing variables and sets `WRFCOIN_ANDROID_UNSIGNED_RELEASE=1`,
the only way Gradle builds a release without signing inputs. The result is
unsigned, never debug-signed. No Gradle patch is needed.

Run with JDK 17 and the Android SDK selected through `JAVA_HOME` and
`ANDROID_HOME`; prepend the JDK bin directory to `PATH`. Save the following as
`dry-run.sh` outside the repository and run it from the disposable worktree with
`nice -n 19 /usr/bin/time -v -o dry-run-time.txt bash dry-run.sh`:

```bash
set -euo pipefail
set +x
unset WRFCOIN_ANDROID_KEYSTORE_PATH WRFCOIN_ANDROID_KEYSTORE_PASSWORD
unset WRFCOIN_ANDROID_KEY_ALIAS WRFCOIN_ANDROID_KEY_PASSWORD
export WRFCOIN_ANDROID_UNSIGNED_RELEASE=1
flutter pub get --enforce-lockfile
flutter build apk --release --build-name 0.1.0 --build-number 1 \
  --dart-define=API_BASE_URL=https://api.example.invalid \
  --dart-define=WRFCOIN_WALLET_AUTH_ORIGIN=https://login.example.invalid \
  --dart-define=WRFCOIN_CHAIN_ID=888 \
  --dart-define=WRFCOIN_NETWORK_ID=testnet \
  --dart-define=TLS_SECURITY_PROFILE=public-release \
  --dart-define=TLS_PIN_SET=cloudflare-universal-v1
```

Record the exact source/toolchain revisions, lock hashes, Flutter migrations,
elapsed time and maximum resident set size reported by GNU time. Its maximum
RSS is not an aggregate peak for concurrent Gradle/Kotlin daemons. Inspect the
APK with `apksigner verify --verbose`: an unsigned artifact must fail signature
verification. Record its SHA-256 and size locally, keep it out of Git, and label
it **UNSIGNED / PLACEHOLDER CONFIGURATION / DO NOT INSTALL OR DISTRIBUTE**.
Restore generated migrations after recording those inputs. A dry-run checksum is not a release checksum.

Before a real release the owner must supply or confirm:

- Approved source and Flutter revisions, version/build number and changelog.
- Public API base URL and backend wallet-login origin, with endpoint acceptance.
- The TLS pin set name (`cloudflare-universal-v1`), after checking the live
  chain against it; see [TLS pins](#tls-pins).
- Chain ID and network ID for the selected deployment.
- Signing keystore, alias, injected passwords and trusted signer fingerprint.
- Physical-device acceptance, including clean install and upgrade with wallet
  preservation, followed by approval of the signed artifact and its checksum.
