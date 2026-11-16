#!/usr/bin/env bash
# Build a sideloadable, debug-signed Android PROFILE APK for testnet dogfooding.
#
# Usage: WRFCOIN_CHAIN_ID=<confirmed-chain-id> scripts/build_profile_apk.sh <https API base URL>
#   e.g. WRFCOIN_CHAIN_ID=888 scripts/build_profile_apk.sh https://wrfcoin.com/api
#
# Public testnet: pass https://wrfcoin.com/api and NO WRFCOIN_WALLET_AUTH_ORIGIN.
# The live login challenge names https://wrfcoin.com, which is the origin the
# app derives from that URL. An origin that differs from the challenge (an old
# tailnet one, for example) makes every login fail.
#
# WRFCOIN_WALLET_AUTH_ORIGIN is only for an API URL on a different origin than
# the backend's wallet-login origin. An API URL with an explicit port is
# refused unless the origin is set explicitly.
#
# Signing: the APK must be signed by exactly one certificate, and its SHA-256
# must equal WRFCOIN_PROFILE_SIGNER_SHA256 (default: the workstation debug key
# that signed every earlier tester APK). Android installs an update only when
# the signer matches, and uninstalling wipes the wallet (allowBackup=false),
# so a build signed by another machine's debug key is refused. These APKs
# never upgrade the public /downloads APK, which is release-signed.
# The APK must also not be debuggable.
#
# Zero-cost path: no release keystore, no store upload, no network publish.
# Profile mode is used on purpose. Release mode requires
# TLS_SECURITY_PROFILE=public-release plus TLS pins (lib/main.dart,
# lib/services/api/tls_pin_configuration.dart); profile requires neither.
#
# Requires ANDROID_HOME (or ANDROID_SDK_ROOT) with build-tools (apksigner) and
# a full JDK 17+ with javac.
# A JRE-only java fails deep inside Gradle with "does not provide the
# required capabilities: [JAVA_COMPILER]".
set -euo pipefail

# SHA-256 of the debug certificate (CN=Android Debug) that signed the earlier
# tester APKs. A public fingerprint, not a secret.
default_profile_signer_sha256=2f62129cfa4f5e34beb271d87f8e5621ea32f830bc74d366f7d560f5afe9d7e2

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "BUILD_PROFILE_APK_REFUSED: $*" >&2
  exit 1
}

[[ -n "${WRFCOIN_CHAIN_ID:-}" ]] || fail "WRFCOIN_CHAIN_ID is required for profile builds"

want_signer="${WRFCOIN_PROFILE_SIGNER_SHA256:-$default_profile_signer_sha256}"
[[ "$want_signer" =~ ^[0-9a-f]{64}$ ]] ||
  fail "WRFCOIN_PROFILE_SIGNER_SHA256 must be 64 lowercase hex characters"

api_url="${1:-${API_BASE_URL:-}}"
[[ -n "$api_url" ]] || fail "API base URL argument is required"
# https + canonical public DNS name: no IP literals, local/reserved or
# placeholder hosts, must resolve to a non-loopback address (shared release gate).
scripts/validate-release-api-host.sh "$api_url" || fail "API base URL rejected: $api_url"

api_authority="${api_url#https://}"
api_authority="${api_authority%%[/?#]*}"
auth_origin="${WRFCOIN_WALLET_AUTH_ORIGIN:-}"
auth_define=()
if [[ -n "$auth_origin" ]]; then
  [[ "$auth_origin" =~ ^https://[^/?#@[:space:]]+$ ]] ||
    fail "WRFCOIN_WALLET_AUTH_ORIGIN must be an https origin with no path, query or trailing slash: $auth_origin"
  scripts/validate-release-api-host.sh "$auth_origin" >/dev/null ||
    fail "WRFCOIN_WALLET_AUTH_ORIGIN rejected: $auth_origin"
  auth_define=(--dart-define=WRFCOIN_WALLET_AUTH_ORIGIN="$auth_origin")
elif [[ "$api_authority" == *:* ]]; then
  fail "API base URL has an explicit port ($api_authority); set WRFCOIN_WALLET_AUTH_ORIGIN to the backend's wallet-login origin, or every login challenge fails to verify"
fi

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$sdk" ]] || fail "ANDROID_HOME / ANDROID_SDK_ROOT is not set"
if ! compgen -G "$sdk/platforms/android-*" >/dev/null; then
  fail "no Android platform installed under $sdk/platforms"
fi
if ! compgen -G "$sdk/build-tools/*" >/dev/null; then
  fail "no Android build-tools installed under $sdk/build-tools"
fi
export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"

# Signer verification is mandatory, so require its tool before spending a build.
apksigner=""
while IFS= read -r candidate; do
  [[ -x "$candidate" ]] && apksigner="$candidate"
done < <(compgen -G "$sdk/build-tools/*/apksigner" | sort -V)
[[ -n "$apksigner" ]] || fail "no executable apksigner under $sdk/build-tools (install build-tools)"
aapt2=""
while IFS= read -r candidate; do
  [[ -x "$candidate" ]] && aapt2="$candidate"
done < <(compgen -G "$sdk/build-tools/*/aapt2" | sort -V)
[[ -n "$aapt2" ]] || fail "no executable aapt2 under $sdk/build-tools (install build-tools)"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is not installed"

javac_bin="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
command -v "$javac_bin" >/dev/null 2>&1 || fail "no javac found (set JAVA_HOME to a full JDK 17+, not a JRE)"
command -v flutter >/dev/null 2>&1 || fail "flutter is not on PATH"

# Never let release keystore material leak into a sideload build.
unset WRFCOIN_ANDROID_KEYSTORE_PATH WRFCOIN_ANDROID_KEYSTORE_PASSWORD \
  WRFCOIN_ANDROID_KEY_ALIAS WRFCOIN_ANDROID_KEY_PASSWORD

# Cap Gradle so concurrent builds on a shared workstation do not OOM
# (android/gradle.properties asks for 8G). Override with GRADLE_OPTS.
export GRADLE_OPTS="${GRADLE_OPTS:--Dorg.gradle.daemon=false -Dorg.gradle.jvmargs=-Xmx3g -Dkotlin.daemon.jvm.options=-Xmx1g}"

# The Flutter Gradle migrator rewrites android/gradle.properties on build;
# restore it afterwards when it started clean so the build leaves no diff.
props=android/gradle.properties
props_clean=0
git diff --quiet -- "$props" 2>/dev/null && props_clean=1
restore_props() {
  if [[ "$props_clean" == 1 ]]; then git checkout -q -- "$props"; fi
}
trap restore_props EXIT

flutter build apk --profile \
  --dart-define=API_BASE_URL="$api_url" \
  --dart-define=TLS_SECURITY_PROFILE=developer \
  --dart-define=WRFCOIN_CHAIN_ID="${WRFCOIN_CHAIN_ID}" \
  --dart-define=WRFCOIN_NETWORK_ID="${WRFCOIN_NETWORK_ID:-testnet}" \
  ${auth_define[@]+"${auth_define[@]}"}

apk=build/app/outputs/flutter-apk/app-profile.apk
[[ -s "$apk" ]] || fail "flutter reported success but $apk is missing"

# Exactly one signer, and it must be the Android Debug cert. Nothing is
# reported as built until this passes.
certs="$("$apksigner" verify --print-certs "$apk" 2>/dev/null)" || fail "apksigner verify failed for $apk"
signer_dns="$(grep -E '^Signer #[0-9]+ certificate DN: ' <<<"$certs" || true)"
[[ "$(grep -c . <<<"$signer_dns")" == 1 ]] || fail "expected exactly one APK signer, got: ${signer_dns:-none}"
[[ "$signer_dns" =~ certificate\ DN:\ (.*,\ )?CN=Android\ Debug(,.*)?$ ]] ||
  fail "APK is not debug-signed ($signer_dns); refusing to label it a sideload build"
signer_sha="$(sed -nE 's/^Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})$/\1/p' <<<"$certs")"
[[ "$signer_sha" == "$want_signer" ]] ||
  fail "APK signer certificate SHA-256 is ${signer_sha:-unknown}, expected $want_signer; it would not install over earlier tester APKs (set WRFCOIN_PROFILE_SIGNER_SHA256 only for a deliberately different key)"
badging="$("$aapt2" dump badging "$apk" 2>/dev/null)" || fail "aapt2 could not read $apk"
grep -q '^package: ' <<<"$badging" || fail "aapt2 printed no package line for $apk"
if grep -q '^application-debuggable' <<<"$badging"; then
  fail "APK is debuggable; profile must set isDebuggable = false (android/app/build.gradle.kts)"
fi
version_line="$(grep '^package: ' <<<"$badging")"

echo "APK=$repo_root/$apk"
echo "SIZE_BYTES=$(wc -c <"$apk" | tr -d ' ')"
echo "SHA256=$(sha256sum "$apk" | cut -d' ' -f1)"
echo "API_BASE_URL=$api_url"
echo "WALLET_AUTH_ORIGIN=${auth_origin:-<derived from API_BASE_URL>}"
echo "$signer_dns"
echo "SIGNER_SHA256=$signer_sha"
echo "VERSION=$(sed -nE "s/.*versionName='([^']*)'.*/\1/p" <<<"$version_line")+$(sed -nE "s/.*versionCode='([^']*)'.*/\1/p" <<<"$version_line")"
echo "PROFILE_APK_OK"
